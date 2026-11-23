import AppKit
import os

/// Entry point. Zettel is an agent app (`LSUIElement = YES`): no Dock icon,
/// no main menu, only a status item in the menu bar.
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let logger = Logger(subsystem: "dev.zettel.Zettel", category: "App")

    private let preferences = AppPreferences()
    private let launchAtLogin = LaunchAtLoginController(service: SystemLoginItemService())
    private var statusItemController: StatusItemController?
    private var settingsWindowController: SettingsWindowController?
    private var panelController: PanelController?
    private var toggleWindowHotKey: GlobalHotKey?

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

    /// Unit tests run inside the app. Skip the menu bar item and the global hotkey
    /// there so tests neither clutter the menu bar nor steal ⌥A from a running Zettel.
    private static var isRunningUnitTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningUnitTests else { return }

        let panel = PanelController(preferences: preferences)
        panelController = panel

        let settings = SettingsWindowController(launchAtLogin: launchAtLogin)
        settingsWindowController = settings

        let hotKeyCombo = preferences.toggleWindowHotKey
        do {
            toggleWindowHotKey = try GlobalHotKey(combo: hotKeyCombo) { panel.toggle() }
        } catch {
            Self.logger.error("Registering hotkey \(hotKeyCombo.displayString, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        }

        statusItemController = StatusItemController(
            launchAtLogin: launchAtLogin,
            actions: StatusMenuActions(
                showWindow: { panel.show() },
                newNote: nil, // Notes arrive in Phase 2.
                openSettings: { settings.show() },
                quit: { NSApp.terminate(nil) }
            ),
            showWindowShortcut: toggleWindowHotKey?.combo
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
