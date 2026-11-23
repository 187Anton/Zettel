import AppKit
import SwiftUI

/// Shows, hides and pins the note window, persists its state and forwards
/// note commands to the editor.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let preferences: AppPreferences
    private let now: () -> Date
    let editor: EditorViewController

    private var panel: NotePanel?
    private var pinButton: NSButton?
    private var positionLabel: NSTextField?
    private var searchView: NSView?
    private var searchModel: NoteSearchViewModel?

    /// Loads all notes for the search (⌘F).
    var loadAllNotes: () -> [Note] = { [] }
    /// Called right before the window appears (backups, expiry, trash cleanup).
    var onWillShow: (() -> Void)?

    private(set) var isPinned: Bool
    /// When the panel last lost focus; app launch counts as well.
    private(set) var lastFocusLoss: Date?

    init(
        preferences: AppPreferences,
        notes: NoteStackModel,
        timerCenter: TimerCenter? = nil,
        pasteCollector: PasteCollector? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.preferences = preferences
        self.now = now
        self.editor = EditorViewController(
            model: notes,
            checkedItemBehavior: { [preferences] in preferences.checkedItemBehavior },
            numberStyle: { [preferences] in preferences.numberStyle },
            timerCenter: timerCenter,
            unitConverter: { [preferences] in preferences.unitConverter },
            pasteCollector: pasteCollector
        )
        self.isPinned = preferences.isPanelPinned
        self.lastFocusLoss = now()
        super.init()
        editor.onStateChange = { [weak self] in self?.updatePositionLabel() }
    }

    var isVisible: Bool { panel?.isVisible ?? false }
    var isKey: Bool { panel?.isKeyWindow ?? false }
    var frame: NSRect? { panel?.frame }

    // MARK: Commands

    /// Global hotkey: show, focus or hide depending on the current state.
    func toggle() {
        switch PanelVisibility.hotKeyAction(isVisible: isVisible, isKey: isKey) {
        case .show: show()
        case .hide: hide()
        }
    }

    func show() {
        let panel = panel ?? makePanel()
        if !panel.isVisible {
            editor.flush() // before maintenance may change the database
            onWillShow?()
            panel.setFrame(initialFrame(), display: false)
            let startFresh = FreshNotePolicy.shouldStartFresh(
                lastFocusLoss: lastFocusLoss,
                now: now(),
                idleMinutes: preferences.newNoteAfterIdleMinutes
            )
            editor.prepareForShow(startFresh: startFresh)
        }
        // The app is never activated; order the panel in and give it keyboard focus.
        panel.orderFrontRegardless()
        panel.makeKey()
        editor.focusTextView()
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        closeSearch()
        editor.relock()
        editor.flush()
        saveFrame()
        lastFocusLoss = now()
        panel.orderOut(nil)
    }

    func togglePin() {
        isPinned.toggle()
        preferences.isPanelPinned = isPinned
        updatePinButton()
    }

    func handle(_ command: PanelCommand) {
        switch command {
        case .togglePin:
            togglePin()
        case .close:
            if isSearching { closeSearch() } else { hide() }
        case .search:
            if isSearching { closeSearch() } else { openSearch() }
        case .export:
            exportCurrentNote()
        case .textBigger, .textSmaller, .textSizeReset:
            switch command {
            case .textBigger: preferences.fontSize += 1
            case .textSmaller: preferences.fontSize -= 1
            default: preferences.fontSize = AppPreferences.defaultFontSize
            }
            editor.setFontSize(preferences.fontSize)
        case .number(let number):
            closeSearch()
            if let resolved = PanelVisibility.numberCommand(
                number,
                inSlotMode: editor.model.isInSlotMode,
                slotShortcutsEnabled: preferences.slotShortcuts
            ) {
                editor.perform(resolved)
            }
        default:
            closeSearch()
            editor.perform(command)
        }
    }

    // MARK: Search (⌘F)

    var isSearching: Bool { searchView != nil }

    func openSearch() {
        guard searchView == nil, let container = panel?.contentView else { return }
        editor.flush()
        let model = NoteSearchViewModel(loadNotes: loadAllNotes) { [weak self] note, restoring in
            self?.closeSearch()
            self?.editor.open(noteID: note.id, restoring: restoring)
        }
        model.reload()
        let hosting = NSHostingView(rootView: NoteSearchView(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        searchView = hosting
        searchModel = model
    }

    func closeSearch() {
        guard let searchView else { return }
        searchView.removeFromSuperview()
        self.searchView = nil
        searchModel = nil
        editor.focusTextView()
    }

    var currentSearchModel: NoteSearchViewModel? { searchModel }

    /// Saves everything; called before the app quits.
    func flush() {
        editor.flush()
        saveFrame()
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        editor.flush()
        lastFocusLoss = now()
        if PanelVisibility.shouldHideOnFocusLoss(isPinned: isPinned) {
            hide()
        }
    }

    func windowDidMove(_ notification: Notification) {
        saveFrame()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        saveFrame()
    }

    /// The close button hides instead of closing, so the panel stays ready.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    /// `undo:` / `redo:` that reach the window use the current note's history.
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        editor.currentUndoManager
    }

    // MARK: Private

    private func makePanel() -> NotePanel {
        let panel = NotePanel(contentRect: initialFrame())
        panel.delegate = self
        panel.onCommand = { [weak self] command in self?.handle(command) }
        panel.contentViewController = editor
        editor.setFontSize(preferences.fontSize)
        installBackground(in: panel)

        let label = NSTextField(labelWithString: "")
        label.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        label.textColor = .tertiaryLabelColor
        label.alignment = .right
        label.toolTip = Strings.Panel.positionHelp

        let button = NSButton(
            image: NSImage(systemSymbolName: "pin", accessibilityDescription: nil) ?? NSImage(),
            target: self,
            action: #selector(pinButtonClicked)
        )
        button.isBordered = false
        button.setButtonType(.momentaryChange)

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 156, height: 28))
        label.frame = NSRect(x: 0, y: 6, width: 118, height: 16)
        button.frame = NSRect(x: 124, y: 2, width: 24, height: 24)
        container.addSubview(label)
        container.addSubview(button)

        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .trailing
        accessory.view = container
        panel.addTitlebarAccessoryViewController(accessory)

        pinButton = button
        positionLabel = label
        self.panel = panel
        updatePinButton()
        updatePositionLabel()
        return panel
    }

    @objc private func pinButtonClicked() {
        togglePin()
    }

    private func updatePinButton() {
        guard let pinButton else { return }
        let description = isPinned ? Strings.Panel.unpin : Strings.Panel.pin
        pinButton.image = NSImage(
            systemSymbolName: isPinned ? "pin.fill" : "pin",
            accessibilityDescription: description
        )
        pinButton.contentTintColor = isPinned ? .controlAccentColor : .secondaryLabelColor
        pinButton.toolTip = "\(description) (⌘P)"
    }

    private func updatePositionLabel() {
        let note = editor.model.current
        var flags = ""
        if note.isLocked { flags += "🔒 " }
        if note.isReadOnly { flags += Strings.Panel.readOnly + " · " }
        positionLabel?.stringValue = flags + editor.model.positionDescription
    }

    // MARK: Appearance

    private var backgroundView: NSVisualEffectView?

    /// Optional see-through window: a vibrant background instead of the solid one.
    private func installBackground(in panel: NotePanel) {
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.translatesAutoresizingMaskIntoConstraints = false
        let root = editor.view
        root.addSubview(effect, positioned: .below, relativeTo: nil)
        NSLayoutConstraint.activate([
            effect.topAnchor.constraint(equalTo: root.topAnchor),
            effect.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            effect.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        ])
        backgroundView = effect
        applyAppearance()
    }

    /// Applies transparency and text size (called when settings change).
    func applyAppearance() {
        guard let panel else { return }
        let transparent = preferences.transparentWindow
        backgroundView?.isHidden = !transparent
        panel.isOpaque = !transparent
        panel.backgroundColor = transparent ? .clear : .textBackgroundColor
        editor.setFontSize(preferences.fontSize)
    }

    // MARK: Export

    /// ⌘⇧E: saves the current note as Markdown, text or PDF.
    func exportCurrentNote() {
        editor.flush()
        let note = editor.model.current
        guard !editor.isShowingLockedNote else {
            NSSound.beep()
            return
        }
        let savePanel = NSSavePanel()
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: NoteExporter.Format.allCases.map(\.title))
        let accessory = NSStackView(views: [NSTextField(labelWithString: Strings.Export.format), popup])
        accessory.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        savePanel.accessoryView = accessory
        savePanel.nameFieldStringValue = NoteExporter.suggestedName(for: note) + ".md"
        savePanel.allowedContentTypes = [NoteExporter.Format.markdown.contentType]
        let formatChanger = ExportFormatChanger(savePanel: savePanel)
        popup.target = formatChanger
        popup.action = #selector(ExportFormatChanger.changed(_:))

        NSApp.activate()
        guard savePanel.runModal() == .OK, let url = savePanel.url else { return }
        let format = NoteExporter.Format.allCases[popup.indexOfSelectedItem]
        do {
            if format == .pdf {
                try NoteExporter.pdfData(of: note).write(to: url)
            } else {
                try NoteExporter.content(of: note, as: format).write(to: url, atomically: true, encoding: .utf8)
            }
        } catch {
            NSAlert(error: error).runModal()
        }
        withExtendedLifetime(formatChanger) {}
    }

    private func initialFrame() -> NSRect {
        let screens = NSScreen.screens
        let mouse = NSEvent.mouseLocation
        let preferred = screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? screens.first
        return PanelFramePlacement.frame(
            saved: preferences.panelFrame,
            screens: screens.map(\.visibleFrame),
            preferredScreen: preferred?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        )
    }

    private func saveFrame() {
        guard let panel, panel.isVisible else { return }
        preferences.panelFrame = panel.frame
    }
}

/// Keeps the save panel's file type in sync with the chosen export format.
@MainActor
private final class ExportFormatChanger: NSObject {
    private weak var savePanel: NSSavePanel?

    init(savePanel: NSSavePanel) {
        self.savePanel = savePanel
    }

    @objc func changed(_ sender: NSPopUpButton) {
        guard let savePanel else { return }
        let format = NoteExporter.Format.allCases[sender.indexOfSelectedItem]
        savePanel.allowedContentTypes = [format.contentType]
        let base = (savePanel.nameFieldStringValue as NSString).deletingPathExtension
        savePanel.nameFieldStringValue = base + "." + format.fileExtension
    }
}
