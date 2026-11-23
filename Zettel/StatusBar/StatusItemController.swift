import AppKit

/// Owns the menu bar icon and attaches the status menu to it.
@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    let statusMenu: StatusMenu

    init(launchAtLogin: LaunchAtLoginController, actions: StatusMenuActions, showWindowShortcut: KeyCombo?) {
        statusMenu = StatusMenu(launchAtLogin: launchAtLogin, actions: actions, showWindowShortcut: showWindowShortcut)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.behavior = .removalAllowed

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "note.text", accessibilityDescription: Strings.appName)
            image?.isTemplate = true
            button.image = image
            button.toolTip = Strings.appName
        }
        statusItem.menu = statusMenu.menu
    }
}
