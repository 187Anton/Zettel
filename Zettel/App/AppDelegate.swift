import AppKit

/// Entry point. Zettel is an agent app (`LSUIElement = YES`): no Dock icon,
/// no main menu, only a status item in the menu bar.
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private var settingsWindowController: SettingsWindowController?
    private let launchAtLogin = LaunchAtLoginController(service: SystemLoginItemService())

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Matches LSUIElement; set explicitly so the policy is also correct when the
        // binary is started without its Info.plist (e.g. from a debugger wrapper).
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = SettingsWindowController(launchAtLogin: launchAtLogin)
        settingsWindowController = settings

        statusItemController = StatusItemController(
            launchAtLogin: launchAtLogin,
            actions: StatusMenuActions(
                newNote: nil, // Notes arrive in Phase 2.
                openSettings: { settings.show() },
                quit: { NSApp.terminate(nil) }
            )
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
