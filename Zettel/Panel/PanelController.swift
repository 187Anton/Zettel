import AppKit

/// Shows, hides and pins the note window and persists its state.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let preferences: AppPreferences
    private var panel: NotePanel?
    private var pinButton: NSButton?

    private(set) var isPinned: Bool

    init(preferences: AppPreferences) {
        self.preferences = preferences
        self.isPinned = preferences.isPanelPinned
        super.init()
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
        }
        // The app is never activated; order the panel in and give it keyboard focus.
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        saveFrame()
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
        }
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
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

    // MARK: Private

    private func makePanel() -> NotePanel {
        let panel = NotePanel(contentRect: initialFrame())
        panel.delegate = self
        panel.onCommand = { [weak self] command in self?.handle(command) }
        panel.contentViewController = PanelContentViewController()

        let button = NSButton(
            image: NSImage(systemSymbolName: "pin", accessibilityDescription: nil) ?? NSImage(),
            target: self,
            action: #selector(pinButtonClicked)
        )
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .trailing
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 36, height: 28))
        button.frame = NSRect(x: 6, y: 2, width: 24, height: 24)
        container.addSubview(button)
        accessory.view = container
        panel.addTitlebarAccessoryViewController(accessory)
        pinButton = button

        self.panel = panel
        updatePinButton()
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
