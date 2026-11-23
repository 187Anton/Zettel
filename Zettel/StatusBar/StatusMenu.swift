import AppKit

/// Callbacks triggered by the status menu. A `nil` action disables its item.
struct StatusMenuActions {
    var showWindow: (@MainActor () -> Void)?
    var newNote: (@MainActor () -> Void)?
    var openSettings: @MainActor () -> Void
    var exportAll: (@MainActor () -> Void)? = nil
    var quit: @MainActor () -> Void
}

/// Builds and maintains the status bar menu. Holds no timers; state is refreshed
/// only when the menu is about to open (`menuNeedsUpdate`).
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    enum ItemID: String, CaseIterable {
        case showWindow = "zettel.menu.showWindow"
        case newNote = "zettel.menu.newNote"
        case exportAll = "zettel.menu.exportAll"
        case settings = "zettel.menu.settings"
        case launchAtLogin = "zettel.menu.launchAtLogin"
        case quit = "zettel.menu.quit"
    }

    let menu: NSMenu
    /// Running timers are listed at the top of the menu with their controls.
    var timerCenter: TimerCenter?
    static let timerItemPrefix = "zettel.menu.timer."
    private let launchAtLogin: LaunchAtLoginController
    private let actions: StatusMenuActions

    /// - Parameter showWindowShortcut: The global hotkey, displayed next to "Notizfenster öffnen".
    init(launchAtLogin: LaunchAtLoginController, actions: StatusMenuActions, showWindowShortcut: KeyCombo? = nil) {
        self.launchAtLogin = launchAtLogin
        self.actions = actions
        self.menu = NSMenu(title: "Zettel")
        super.init()

        menu.autoenablesItems = false
        menu.delegate = self

        let showItem = makeItem(.showWindow, title: Strings.Menu.showWindow, key: "", action: #selector(showWindow))
        if let shortcut = showWindowShortcut, let key = shortcut.keyName, key.count == 1, key.allSatisfy({ $0.isLetter || $0.isNumber }) {
            // Display only: the status menu is not open when the hotkey fires.
            showItem.keyEquivalent = key.lowercased()
            showItem.keyEquivalentModifierMask = shortcut.modifiers.eventModifierFlags
        }
        menu.addItem(showItem)
        menu.addItem(makeItem(.newNote, title: Strings.Menu.newNote, key: "n", action: #selector(newNote)))
        menu.addItem(makeItem(.exportAll, title: Strings.Menu.exportAll, key: "", action: #selector(exportAll)))
        menu.addItem(.separator())
        menu.addItem(makeItem(.settings, title: Strings.Menu.settings, key: ",", action: #selector(openSettings)))
        menu.addItem(makeItem(.launchAtLogin, title: Strings.Menu.launchAtLogin, key: "", action: #selector(toggleLaunchAtLogin)))
        menu.addItem(.separator())
        menu.addItem(makeItem(.quit, title: Strings.Menu.quit, key: "q", action: #selector(quit)))

        update()
    }

    func item(_ id: ItemID) -> NSMenuItem? {
        menu.items.first { $0.identifier?.rawValue == id.rawValue }
    }

    /// Syncs item state with the current app state.
    func update() {
        launchAtLogin.refresh()
        updateTimerItems()

        item(.showWindow)?.isEnabled = actions.showWindow != nil
        item(.newNote)?.isEnabled = actions.newNote != nil
        item(.exportAll)?.isEnabled = actions.exportAll != nil

        if let loginItem = item(.launchAtLogin) {
            loginItem.state = launchAtLogin.needsApproval ? .mixed : (launchAtLogin.isEnabled ? .on : .off)
            loginItem.toolTip = launchAtLogin.needsApproval ? Strings.Menu.launchAtLoginNeedsApproval : nil
        }
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        update()
    }

    // MARK: Actions

    @objc private func showWindow() {
        actions.showWindow?()
    }

    @objc private func newNote() {
        actions.newNote?()
    }

    @objc private func exportAll() {
        actions.exportAll?()
    }

    /// The global hotkey changed: show the new one next to "Notizfenster öffnen".
    func updateShortcut(_ shortcut: KeyCombo?) {
        guard let item = item(.showWindow) else { return }
        if let shortcut, let key = shortcut.keyName, key.count == 1, key.allSatisfy({ $0.isLetter || $0.isNumber }) {
            item.keyEquivalent = key.lowercased()
            item.keyEquivalentModifierMask = shortcut.modifiers.eventModifierFlags
        } else {
            item.keyEquivalent = ""
        }
    }

    @objc private func openSettings() {
        actions.openSettings()
    }

    @objc private func toggleLaunchAtLogin() {
        if launchAtLogin.needsApproval {
            launchAtLogin.openSystemSettings()
        } else {
            launchAtLogin.toggle()
        }
        update()
    }

    @objc private func quit() {
        actions.quit()
    }

    // MARK: Helpers

    // MARK: Timers

    private func updateTimerItems() {
        for item in menu.items where item.identifier?.rawValue.hasPrefix(Self.timerItemPrefix) == true {
            menu.removeItem(item)
        }
        guard let timerCenter else { return }
        let timers = timerCenter.activeTimers
        guard !timers.isEmpty else { return }

        let date = timerCenter.date
        var index = 0
        for timer in timers {
            let item = NSMenuItem(title: "\(TimerFormat.title(timer))  \(TimerFormat.status(timer, at: date))", action: nil, keyEquivalent: "")
            item.identifier = NSUserInterfaceItemIdentifier(Self.timerItemPrefix + timer.id.uuidString)
            item.image = NSImage(systemSymbolName: "timer", accessibilityDescription: nil)
            let submenu = NSMenu()
            for (title, control) in [
                (timer.isPaused ? Strings.Timer.resume : Strings.Timer.pause, TimerControl.togglePause),
                (Strings.Timer.restart, .restart),
                (Strings.Timer.stop, .stop),
            ] {
                let entry = NSMenuItem(title: title, action: #selector(timerControlChosen(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = TimerMenuAction(id: timer.id, control: control)
                submenu.addItem(entry)
            }
            item.submenu = submenu
            menu.insertItem(item, at: index)
            index += 1
        }
        let separator = NSMenuItem.separator()
        separator.identifier = NSUserInterfaceItemIdentifier(Self.timerItemPrefix + "separator")
        menu.insertItem(separator, at: index)
    }

    @objc private func timerControlChosen(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? TimerMenuAction else { return }
        timerCenter?.apply(action.control, to: action.id)
    }

    private func makeItem(_ id: ItemID, title: String, key: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.identifier = NSUserInterfaceItemIdentifier(id.rawValue)
        item.target = self
        return item
    }
}

private final class TimerMenuAction: NSObject {
    let id: UUID
    let control: TimerControl

    init(id: UUID, control: TimerControl) {
        self.id = id
        self.control = control
    }
}
