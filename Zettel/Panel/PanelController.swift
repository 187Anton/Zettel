import AppKit

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

    private(set) var isPinned: Bool
    /// When the panel last lost focus; app launch counts as well.
    private(set) var lastFocusLoss: Date?

    init(preferences: AppPreferences, notes: NoteStackModel, timerCenter: TimerCenter? = nil, now: @escaping () -> Date = Date.init) {
        self.preferences = preferences
        self.now = now
        self.editor = EditorViewController(
            model: notes,
            checkedItemBehavior: { [preferences] in preferences.checkedItemBehavior },
            numberStyle: { [preferences] in preferences.numberStyle },
            timerCenter: timerCenter
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
        case .togglePin: togglePin()
        case .close: hide()
        default: editor.perform(command)
        }
    }

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

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 96, height: 28))
        label.frame = NSRect(x: 0, y: 6, width: 58, height: 16)
        button.frame = NSRect(x: 64, y: 2, width: 24, height: 24)
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
        positionLabel?.stringValue = editor.model.positionDescription
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
