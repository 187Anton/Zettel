import AppKit

/// Main menu of the app. Invisible most of the time (agent app), but it provides
/// the standard editing shortcuts (⌘Z, ⌘X, ⌘C, ⌘V, ⌘A) to the text view and shows
/// up in the menu bar while the settings window is active.
@MainActor
enum MainMenu {
    static func make(settingsTarget: AnyObject, settingsAction: Selector) -> NSMenu {
        let mainMenu = NSMenu()

        let appMenu = NSMenu(title: Strings.appName)
        appMenu.addItem(withTitle: Strings.MainMenu.about, action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let settings = appMenu.addItem(withTitle: Strings.Menu.settings, action: settingsAction, keyEquivalent: ",")
        settings.target = settingsTarget
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: Strings.Menu.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        addSubmenu(appMenu, to: mainMenu)

        let editMenu = NSMenu(title: Strings.MainMenu.edit)
        editMenu.addItem(withTitle: Strings.MainMenu.undo, action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: Strings.MainMenu.redo, action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: Strings.MainMenu.cut, action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: Strings.MainMenu.copy, action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: Strings.MainMenu.paste, action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: Strings.MainMenu.selectAll, action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        addSubmenu(editMenu, to: mainMenu)

        return mainMenu
    }

    private static func addSubmenu(_ submenu: NSMenu, to menu: NSMenu) {
        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
    }
}
