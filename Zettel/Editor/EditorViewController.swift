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
    private let timerCenter: TimerCenter?
    private let unitConverter: () -> UnitConverter
    private var defaultsObserver: NSObjectProtocol?
    private var timerObserver: NSObjectProtocol?
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
        numberStyle: @escaping () -> NumberStyle = { .german },
        timerCenter: TimerCenter? = nil,
        unitConverter: @escaping () -> UnitConverter = { .none }
    ) {
        self.model = model
        self.checkedItemBehavior = checkedItemBehavior
        self.numberStyle = numberStyle
        self.timerCenter = timerCenter
        self.unitConverter = unitConverter
        super.init(nibName: nil, bundle: nil)
        // Timer display: refreshed per tick, but only while the window is visible.
        timerObserver = NotificationCenter.default.addObserver(
            forName: TimerCenter.didChange, object: timerCenter, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isViewLoaded, self.view.window?.isVisible == true else { return }
                self.updateAnnotations()
            }
        }
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
        textView.onReturn = { [weak self] line, linesAbove in
            self?.handleReturn(line: line, linesAbove: linesAbove) ?? .normal
        }
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        // ⌘⇧F: the standard find bar (with replace) at the top of the note.
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
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
        case .findReplace:
            showFindReplace()
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
            case .archive:
                let removedID = try model.archiveCurrent()
                undoManagers[removedID] = nil
                selections[removedID] = nil
            case .toggleSlots: try model.toggleMode()
            case .selectSlot(let slot): try model.selectSlot(slot)
            case .togglePin, .close, .toggleCheckbox, .cycleListType, .number, .search, .findReplace:
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

    /// Opens a note found in the search; archived or trashed notes are restored first.
    func open(noteID: String, restoring: Bool) {
        flush()
        rememberSelection()
        do {
            if restoring {
                try model.restoreAndOpen(noteID: noteID)
            } else {
                try model.open(noteID: noteID)
            }
        } catch {
            Self.logger.error("Opening note failed: \(error.localizedDescription, privacy: .public)")
        }
        forgetRemovedNotes()
        render()
    }

    /// Everything changed underneath (backup restored): reload and forget undo history.
    func reloadFromStore() {
        autosave.cancel()
        do {
            try model.reloadAll()
        } catch {
            Self.logger.error("Reloading notes failed: \(error.localizedDescription, privacy: .public)")
        }
        undoManagers = [:]
        selections = [:]
        displayedNoteID = nil
        render()
    }

    func showFindReplace() {
        let item = NSMenuItem()
        item.tag = NSTextFinder.Action.showReplaceInterface.rawValue
        textView.performTextFinderAction(item)
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
        var annotations: [Int: LineAnnotation] = switch KeywordHeader(text: text)?.keyword {
        case .math: MathSheet.evaluate(lines: lines(), from: 1, style: numberStyle(), converter: unitConverter())
        case let keyword? where [.sum, .avg, .count].contains(keyword):
            AggregateSheet.evaluate(keyword, lines: lines(), style: numberStyle(), converter: unitConverter())
        default: [:]
        }
        annotations.merge(timerAnnotations(lines: lines())) { _, timer in timer }
        styler.updateAnnotations(annotations, in: storage)
        textView.annotations = annotations
    }

    // MARK: Timers

    /// Status next to each line that started a timer.
    private func timerAnnotations(lines: [String]) -> [Int: LineAnnotation] {
        guard let timerCenter, timerCenter.timers.contains(where: { $0.noteID == model.current.id }) else { return [:] }
        let date = timerCenter.date
        var annotations: [Int: LineAnnotation] = [:]
        for (index, line) in lines.enumerated() {
            let content = ListLine(display: line).content
            guard case .start? = TimerCommand(line: content),
                  let timer = timerCenter.timer(noteID: model.current.id, line: content)
            else { continue }
            let active = !timer.isPaused && timer.status(at: date) != .finished
            annotations[index] = LineAnnotation(text: TimerFormat.status(timer, at: date), kind: active ? .result : .info)
        }
        return annotations
    }

    /// Return at the end of a `timer …` line starts or controls a timer.
    func handleReturn(line: String, linesAbove: [String]) -> NoteTextView.ReturnAction {
        guard let timerCenter else { return .normal }
        let content = ListLine(display: line).content
        let noteID = model.current.id
        switch TimerCommand(line: content) {
        case .start(let spec)?:
            if let existing = timerCenter.timer(noteID: noteID, line: content),
               existing.status(at: timerCenter.date) != .finished {
                return .normal // already running for this line
            }
            timerCenter.start(spec, noteID: noteID, line: content)
            return .normal
        case .control(let control)?:
            let above = linesAbove.map { ListLine(display: $0).content }
            if let target = timerCenter.target(noteID: noteID, linesAbove: above) {
                timerCenter.apply(control, to: target.id)
            }
            return .clearLine
        case nil:
            return .normal
        }
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

    /// Drops empty undo histories of notes that are not in the stack anymore
    /// (e.g. deleted blank notes). Slot notes keep their history across switches;
    /// trashed and archived notes are dropped where they are removed.
    private func forgetRemovedNotes() {
        let ids = Set(model.notes.map(\.id)).union([model.current.id])
        undoManagers = undoManagers.filter { ids.contains($0.key) || $0.value.canUndo || $0.value.canRedo }
        selections = selections.filter { ids.contains($0.key) || undoManagers[$0.key] != nil }
    }
}
