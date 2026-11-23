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
    private let pasteCollector: PasteCollector?
    private let hidesMarkdownMarkers: () -> Bool
    private var pasteObserver: NSObjectProtocol?
    /// Asks for Touch ID / password. Replaced in tests.
    var authenticate: (String) async -> Bool = { await Authentication.deviceOwner(reason: $0) }
    /// Locked notes opened in this session; cleared when the window hides.
    private var unlockedNoteIDs: Set<String> = []
    private var lockOverlay: NSView!

    /// Keyword of the displayed note at the last update, to notice changes.
    private var lastKeyword: (noteID: String, keyword: Keyword?)?
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
        unitConverter: @escaping () -> UnitConverter = { .none },
        pasteCollector: PasteCollector? = nil,
        hidesMarkdownMarkers: @escaping () -> Bool = { false }
    ) {
        self.hidesMarkdownMarkers = hidesMarkdownMarkers
        self.model = model
        self.checkedItemBehavior = checkedItemBehavior
        self.numberStyle = numberStyle
        self.timerCenter = timerCenter
        self.unitConverter = unitConverter
        self.pasteCollector = pasteCollector
        super.init(nibName: nil, bundle: nil)
        pasteObserver = NotificationCenter.default.addObserver(
            forName: PasteCollector.didChange, object: pasteCollector, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isViewLoaded else { return }
                self.updateAnnotations()
            }
        }
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
            MainActor.assumeIsolated {
                self?.updateAnnotations()
                if self?.isViewLoaded == true { self?.textView.updateLinkCollapsing() }
            }
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
        textView.onEscape = { [weak self] in self?.handleEscape() ?? false }
        textView.hidesMarkdownMarkers = { [weak self] in self?.hidesMarkdownMarkers() ?? false }
        textView.onKeywordChosen = { [weak self] keyword in
            guard let self, keyword == .paste else { return }
            self.pasteCollector?.start(noteID: self.model.current.id)
        }
        textView.onDidWritePasteboard = { [weak self] in self?.pasteCollector?.ignoreCurrentContents() }
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

        let lockOverlay = makeLockOverlay()
        root.addSubview(lockOverlay)
        NSLayoutConstraint.activate([
            lockOverlay.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            lockOverlay.centerYAnchor.constraint(equalTo: root.centerYAnchor),
        ])
        self.lockOverlay = lockOverlay
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
        case .format(let style):
            textView.toggleFormat(style)
            return
        case .toggleComment:
            textView.toggleComment(prefix: commentPrefix)
            return
        case .openLink:
            textView.openLinkAtCursor()
            return
        case .toggleLock:
            Task { await toggleLock() }
            return
        case .toggleReadOnly:
            toggleReadOnly()
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
            case .togglePin, .close, .toggleCheckbox, .cycleListType, .number, .search, .findReplace,
                 .format, .toggleComment, .openLink, .export, .toggleLock, .toggleReadOnly,
                 .textBigger, .textSmaller, .textSizeReset:
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

    /// `//`, or the line comment of the language in `code` notes.
    private var commentPrefix: String {
        guard let header = KeywordHeader(text: textView.string), header.keyword == .code else { return "//" }
        return SyntaxHighlighter.language(named: header.title).commentPrefix
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
        let header = KeywordHeader(text: text)
        updateMode(for: header, storage: storage)
        let lines = { text.components(separatedBy: "\n") }
        var annotations: [Int: LineAnnotation] = switch header?.keyword {
        case .math: MathSheet.evaluate(lines: lines(), from: 1, style: numberStyle(), converter: unitConverter())
        case let keyword? where [.sum, .avg, .count].contains(keyword):
            AggregateSheet.evaluate(keyword, lines: lines(), style: numberStyle(), converter: unitConverter())
        default: [:]
        }
        annotations.merge(timerAnnotations(lines: lines())) { _, timer in timer }
        if header?.keyword == .paste {
            annotations[0] = pasteCollector?.isCollecting(into: model.current.id) == true
                ? LineAnnotation(text: Strings.Paste.active, kind: .result)
                : LineAnnotation(text: Strings.Paste.inactive, kind: .info)
        }
        styler.updateAnnotations(annotations, in: storage)
        textView.annotations = annotations
    }

    // MARK: Lock & read-only

    var isShowingLockedNote: Bool {
        model.current.isLocked && !unlockedNoteIDs.contains(model.current.id)
    }

    /// Hides locked notes behind the overlay and disables editing where needed.
    private func applyAccess() {
        guard let textView else { return }
        let hidden = isShowingLockedNote
        textView.isHidden = hidden
        lockOverlay.isHidden = !hidden
        textView.isEditable = !hidden && !model.current.isReadOnly
        if hidden, textView.window?.firstResponder === textView {
            textView.window?.makeFirstResponder(nil)
        }
    }

    /// ⌘⇧L: locks an unlocked note; on a hidden locked note asks for Touch ID to show
    /// it; on a shown locked note removes the lock.
    func toggleLock() async {
        flush()
        let note = model.current
        do {
            if !note.isLocked {
                try model.setCurrentLocked(true)
                unlockedNoteIDs.remove(note.id)
            } else if unlockedNoteIDs.contains(note.id) {
                try model.setCurrentLocked(false)
            } else {
                await unlockCurrent()
                return
            }
        } catch {
            Self.logger.error("Changing lock failed: \(error.localizedDescription, privacy: .public)")
        }
        applyAccess()
        onStateChange?()
    }

    func unlockCurrent() async {
        let id = model.current.id
        guard await authenticate(Strings.Lock.reason) else { return }
        unlockedNoteIDs.insert(id)
        applyAccess()
        focusTextView()
        onStateChange?()
    }

    func toggleReadOnly() {
        flush()
        do {
            try model.toggleCurrentReadOnly()
        } catch {
            Self.logger.error("Changing read-only failed: \(error.localizedDescription, privacy: .public)")
        }
        applyAccess()
        onStateChange?()
    }

    /// Hides unlocked notes again (window closed).
    func relock() {
        unlockedNoteIDs = []
        if isViewLoaded { applyAccess() }
    }

    private func makeLockOverlay() -> NSView {
        let image = NSImageView(image: NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil) ?? NSImage())
        image.symbolConfiguration = .init(pointSize: 28, weight: .regular)
        image.contentTintColor = .secondaryLabelColor
        let label = NSTextField(labelWithString: Strings.Lock.title)
        label.textColor = .secondaryLabelColor
        let button = NSButton(title: Strings.Lock.unlock, target: self, action: #selector(unlockClicked))
        button.keyEquivalent = "\r"
        let stack = NSStackView(views: [image, label, button])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isHidden = true
        return stack
    }

    @objc private func unlockClicked() {
        Task { await unlockCurrent() }
    }

    // MARK: Text size

    func setFontSize(_ size: CGFloat) {
        guard let textView, let storage = textView.textStorage else { return }
        styler.font = .systemFont(ofSize: size)
        textView.font = styler.font
        textView.defaultParagraphStyle = styler.baseParagraphStyle
        textView.typingAttributes = styler.baseAttributes
        styler.styleAll(storage)
        if let layoutManager = textView.layoutManager {
            layoutManager.invalidateGlyphs(forCharacterRange: NSRange(location: 0, length: storage.length), changeInLength: 0, actualCharacterRange: nil)
        }
        textView.needsDisplay = true
    }

    // MARK: Modes (code, paste)

    /// Reacts to keyword changes: syntax colors for `code`, starting/stopping `paste`.
    private func updateMode(for header: KeywordHeader?, storage: NSTextStorage) {
        let language = header?.keyword == .code ? SyntaxHighlighter.language(named: header?.title) : nil
        if language != styler.codeLanguage {
            styler.codeLanguage = language
            styler.styleAll(storage)
        }

        let noteID = model.current.id
        let keyword = header?.keyword
        let previous = lastKeyword
        // Record first: starting/stopping posts a notification that calls back here.
        lastKeyword = (noteID, keyword)
        if let previous, previous.noteID == noteID, previous.keyword != keyword {
            if keyword == .paste {
                pasteCollector?.start(noteID: noteID)
            } else if previous.keyword == .paste, pasteCollector?.isCollecting(into: noteID) == true {
                pasteCollector?.stop()
            }
        }
    }

    /// Esc ends an active paste mode of the shown note (instead of closing the window).
    private func handleEscape() -> Bool {
        guard let pasteCollector, pasteCollector.isCollecting(into: model.current.id) else { return false }
        pasteCollector.stop()
        return true
    }

    /// Appends collected clipboard text if that note is shown. Returns `false` otherwise.
    @discardableResult
    func appendCollected(_ text: String, toNote noteID: String) -> Bool {
        guard isViewLoaded, model.current.id == noteID, let textView else { return false }
        let current = textView.string as NSString
        let addition = NoteFormat.display(fromMarkdown: text.trimmingCharacters(in: .newlines))
        let separator = current.length == 0 || textView.string.hasSuffix("\n") ? "" : "\n"
        let end = NSRange(location: current.length, length: 0)
        let inserted = separator + addition
        textView.apply(TextEdit(range: end, replacement: inserted, selection: NSRange(location: current.length + (inserted as NSString).length, length: 0)))
        return true
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

    func textViewDidChangeSelection(_ notification: Notification) {
        textView?.updateLinkCollapsing()
    }

    func textDidChange(_ notification: Notification) {
        textView.updateLinkCollapsing()
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
            textView.updateLinkCollapsing()
        }
        applyAccess()
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
