import AppKit
import os

/// Shows the current note in a text view, autosaves it and runs note commands.
///
/// Every note has its own `UndoManager`, so ⌘Z never undoes typing from another note.
@MainActor
final class EditorViewController: NSViewController, NSTextViewDelegate {
    private static let logger = Logger(subsystem: "dev.zettel.Zettel", category: "Editor")
    static let autosaveDelay: Duration = .milliseconds(500)

    let model: NoteStackModel
    /// Called after the current note or its position changed.
    var onStateChange: (() -> Void)?

    private(set) var textView: NoteTextView!
    private let styler = ListStyler(font: .systemFont(ofSize: 14))
    private let checkedItemBehavior: () -> CheckedItemBehavior
    private let numberStyle: () -> NumberStyle
    private var defaultsObserver: NSObjectProtocol?
    private var scrollView: NoteScrollView!
    private var displayedNoteID: String?
    private var undoManagers: [String: UndoManager] = [:]
    private var selections: [String: NSRange] = [:]
    private lazy var autosave = Debouncer(delay: Self.autosaveDelay) { [weak self] in
        self?.save()
    }

    init(
        model: NoteStackModel,
        checkedItemBehavior: @escaping () -> CheckedItemBehavior = { .keep },
        numberStyle: @escaping () -> NumberStyle = { .german }
    ) {
        self.model = model
        self.checkedItemBehavior = checkedItemBehavior
        self.numberStyle = numberStyle
        super.init(nibName: nil, bundle: nil)
        // Number format changed in the settings: recalculate (no polling).
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateAnnotations() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: View

    override func loadView() {
        let root = NSView(frame: NSRect(origin: .zero, size: PanelFramePlacement.defaultSize))

        let scrollView = NoteScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.onSwipe = { [weak self] direction in
            // Like "back" in a browser: fingers to the right go to the older note.
            self?.perform(direction == .right ? .showOlder : .showNewer)
        }

        // TextKit 1 for predictable line geometry (inline results, checkboxes later).
        let textView = NoteTextView(usingTextLayoutManager: false)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 12, height: 8)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = styler.font
        textView.textColor = .textColor
        textView.defaultParagraphStyle = styler.baseParagraphStyle
        textView.typingAttributes = styler.baseAttributes
        textView.textStorage?.delegate = styler
        textView.layoutManager?.delegate = styler
        textView.checkedItemBehavior = checkedItemBehavior
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.delegate = self

        scrollView.documentView = textView
        root.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        ])

        self.scrollView = scrollView
        self.textView = textView
        view = root
        render()
    }

    // MARK: Commands

    func perform(_ command: PanelCommand) {
        // Text commands stay within the note; autosave picks them up as typing.
        switch command {
        case .toggleCheckbox:
            textView.toggleCheckbox()
            return
        case .cycleListType:
            textView.cycleListType()
            return
        default:
            break
        }

        autosave.cancel()
        rememberSelection()
        do {
            switch command {
            case .newNote: try model.createNote()
            case .showOlder: try model.showOlder()
            case .showNewer: try model.showNewer()
            case .showNewest: try model.showNewest()
            case .bringToFront: try model.bringCurrentToFront()
            case .trash:
                let removedID = try model.trashCurrent()
                undoManagers[removedID] = nil
                selections[removedID] = nil
            case .togglePin, .close, .toggleCheckbox, .cycleListType:
                break // handled by the panel controller / above
            }
        } catch {
            Self.logger.error("Note command \(String(describing: command), privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
        forgetRemovedNotes()
        render()
    }

    /// Called right before the window is shown.
    func prepareForShow(startFresh: Bool) {
        flush()
        rememberSelection()
        do {
            try model.prepareForShow(startFresh: startFresh)
        } catch {
            Self.logger.error("Preparing notes failed: \(error.localizedDescription, privacy: .public)")
        }
        forgetRemovedNotes()
        render()
    }

    /// Saves pending changes immediately (window hidden, app quitting).
    func flush() {
        autosave.cancel()
        save()
    }

    func focusTextView() {
        _ = view // make sure the view is loaded
        view.window?.makeFirstResponder(textView)
    }

    /// Tests turn this off to open and close undo groups themselves, since no
    /// run loop ends the "event" between simulated key presses.
    var undoGroupsByEvent = true

    /// Undo manager of the note currently shown.
    var currentUndoManager: UndoManager {
        let id = model.current.id
        if let manager = undoManagers[id] { return manager }
        let manager = UndoManager()
        manager.groupsByEvent = undoGroupsByEvent
        manager.levelsOfUndo = 500
        undoManagers[id] = manager
        return manager
    }

    // MARK: NSTextViewDelegate

    /// Recalculates `math` results. Cheap; runs after every change.
    func updateAnnotations() {
        guard let textView, let storage = textView.textStorage else { return }
        let text = textView.string
        let lines = { text.components(separatedBy: "\n") }
        let annotations: [Int: LineAnnotation] = switch KeywordHeader(text: text)?.keyword {
        case .math: MathSheet.evaluate(lines: lines(), from: 1, style: numberStyle())
        case let keyword? where [.sum, .avg, .count].contains(keyword):
            AggregateSheet.evaluate(keyword, lines: lines(), style: numberStyle())
        default: [:]
        }
        styler.updateAnnotations(annotations, in: storage)
        textView.annotations = annotations
    }

    func textDidChange(_ notification: Notification) {
        updateAnnotations()
        // The editor shows ☐/☑/•, the note is stored as Markdown.
        model.updateCurrentText(NoteFormat.markdown(fromDisplay: textView.string))
        autosave.schedule()
    }

    func undoManager(for view: NSTextView) -> UndoManager? {
        currentUndoManager
    }

    // MARK: Private

    private func save() {
        do {
            try model.save()
        } catch {
            Self.logger.error("Saving note failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Shows the current note if it differs from the displayed one.
    private func render() {
        guard let textView else { return }
        let note = model.current
        if displayedNoteID != note.id {
            textView.breakUndoCoalescing()
            let text = NoteFormat.display(fromMarkdown: note.text)
            textView.string = text
            textView.typingAttributes = styler.baseAttributes
            let length = (text as NSString).length
            let selection = selections[note.id] ?? NSRange(location: length, length: 0)
            textView.setSelectedRange(NSRange(
                location: min(selection.location, length),
                length: min(selection.length, length - min(selection.location, length))
            ))
            textView.scrollRangeToVisible(textView.selectedRange())
            displayedNoteID = note.id
            textView.closeKeywordPicker()
            updateAnnotations()
        }
        onStateChange?()
    }

    private func rememberSelection() {
        guard let displayedNoteID, let textView else { return }
        textView.breakUndoCoalescing()
        selections[displayedNoteID] = textView.selectedRange()
    }

    /// Drops undo history of notes that are no longer in the stack (e.g. blank ones).
    private func forgetRemovedNotes() {
        let ids = Set(model.notes.map(\.id))
        undoManagers = undoManagers.filter { ids.contains($0.key) }
        selections = selections.filter { ids.contains($0.key) }
    }
}
