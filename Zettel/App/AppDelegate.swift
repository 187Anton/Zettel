import AppKit
import os

/// Entry point. Zettel is an agent app (`LSUIElement = YES`): no Dock icon,
/// only a status item in the menu bar.
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
    private var timerCenter: TimerCenter?
    private var timerAlerts: TimerAlerts?
    private var store: NoteStore?
    private var backups: BackupManager?

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

    /// Unit tests run inside the app. Skip the menu bar item, the hotkey and the
    /// real database there, so tests neither clutter the menu bar, steal ⌥A from a
    /// running Zettel nor touch the user's notes.
    private static var isRunningUnitTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningUnitTests else { return }

        NSApp.mainMenu = MainMenu.make(settingsTarget: self, settingsAction: #selector(openSettings))

        guard let notes = openNotes() else {
            NSApp.terminate(nil)
            return
        }
        if let store, let directory = try? BackupManager.defaultDirectory() {
            backups = BackupManager(store: store, directory: directory)
        }
        runMaintenance()
        try? notes.reloadAll()
        let timers = TimerCenter()
        timerCenter = timers
        timerAlerts = TimerAlerts(preferences: preferences, timerCenter: timers)

        #if DEBUG
        // Resource measurement with a running timer (README): `--args -ZettelMeasureTimer`.
        if ProcessInfo.processInfo.arguments.contains("-ZettelMeasureTimer") {
            timers.start(TimerSpec(kind: .countdown(600), name: "Messung"), noteID: "measurement", line: "timer 10: Messung")
        }
        #endif

        let panel = PanelController(preferences: preferences, notes: notes, timerCenter: timers)
        panel.loadAllNotes = { [weak self] in (try? self?.store?.allNotes()) ?? [] }
        panel.onWillShow = { [weak self] in self?.runMaintenance() }
        panelController = panel

        let settings = SettingsWindowController(launchAtLogin: launchAtLogin, backups: backups) { [weak panel] in
            panel?.editor.reloadFromStore()
        }
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
                newNote: {
                    panel.show()
                    panel.handle(.newNote)
                },
                openSettings: { settings.show() },
                quit: { NSApp.terminate(nil) }
            ),
            showWindowShortcut: toggleWindowHotKey?.combo,
            timerCenter: timers,
            showsTimer: { [preferences] in preferences.timerInMenuBar }
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        panelController?.flush()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func openSettings() {
        settingsWindowController?.show()
    }

    /// Backup if due, expiry of unchanged notes, trash cleanup. No timer: runs at
    /// launch and whenever the note window opens.
    private func runMaintenance() {
        guard let store else { return }
        do {
            try backups?.backupIfDue(interval: preferences.backupInterval)
            try NoteRetention.apply(expiry: preferences.noteExpiry, trash: preferences.trashPeriod, to: store, now: Date())
        } catch {
            Self.logger.error("Maintenance failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Opens the note database. If that fails, the user is warned and Zettel runs
    /// with a temporary in-memory store rather than not at all.
    private func openNotes() -> NoteStackModel? {
        do {
            let store = try NoteStore.openDefault()
            self.store = store
            return try NoteStackModel(store: store)
        } catch {
            Self.logger.fault("Opening note database failed: \(error.localizedDescription, privacy: .public)")
            NSApp.activate()
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = Strings.Settings.databaseErrorTitle
            alert.informativeText = Strings.Settings.databaseErrorMessage + error.localizedDescription
            alert.runModal()
            guard let store = try? NoteStore.inMemory() else { return nil }
            self.store = store
            return try? NoteStackModel(store: store)
        }
    }
}
