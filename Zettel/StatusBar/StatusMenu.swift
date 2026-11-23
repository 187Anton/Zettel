import AppKit

/// Callbacks triggered by the status menu. A `nil` action disables its item.
struct StatusMenuActions {
    var showWindow: (@MainActor () -> Void)?
    var newNote: (@MainActor () -> Void)?
    var openSettings: @MainActor () -> Void
    var quit: @MainActor () -> Void
}

/// Builds and maintains the status bar menu. Holds no timers; state is refreshed
/// only when the menu is about to open (`menuNeedsUpdate`).
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    enum ItemID: String, CaseIterable {
        case showWindow = "zettel.menu.showWindow"
        case newNote = "zettel.menu.newNote"
        case settings = "zettel.menu.settings"
        case launchAtLogin = "zettel.menu.launchAtLogin"
        case quit = "zettel.menu.quit"
    }

    let menu: NSMenu
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
        if let shortcut = showWindowShortcut, let key = shortcut.keyName, key.count == 1 {
            // Display only: the status menu is not open when the hotkey fires.
            showItem.keyEquivalent = key.lowercased()
            showItem.keyEquivalentModifierMask = shortcut.modifiers.eventModifierFlags
        }
        menu.addItem(showItem)
        menu.addItem(makeItem(.newNote, title: Strings.Menu.newNote, key: "n", action: #selector(newNote)))
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

        item(.showWindow)?.isEnabled = actions.showWindow != nil
        item(.newNote)?.isEnabled = actions.newNote != nil

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

    private func makeItem(_ id: ItemID, title: String, key: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.identifier = NSUserInterfaceItemIdentifier(id.rawValue)
        item.target = self
        return item
    }
}
