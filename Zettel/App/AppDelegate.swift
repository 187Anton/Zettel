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
    private var pasteCollector: PasteCollector?
    private var defaultsObserver: NSObjectProtocol?
    /// Last applied appearance values, to react only to real changes.
    private var appliedAppearance: (AppPreferences.Theme, Double, Bool)?

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

        let collector = PasteCollector()
        pasteCollector = collector

        let panel = PanelController(preferences: preferences, notes: notes, timerCenter: timers, pasteCollector: collector)
        collector.onCollect = { [weak self, weak panel] noteID, text in
            guard panel?.editor.appendCollected(text, toNote: noteID) != true else { return }
            self?.appendToStoredNote(noteID: noteID, text: text)
        }
        panel.loadAllNotes = { [weak self] in (try? self?.store?.allNotes()) ?? [] }
        panel.onWillShow = { [weak self] in self?.runMaintenance() }
        panelController = panel

        let settings = SettingsWindowController(launchAtLogin: launchAtLogin, backups: backups) { [weak panel] in
            panel?.editor.reloadFromStore()
        }
        settingsWindowController = settings

        registerHotKey()

        statusItemController = StatusItemController(
            launchAtLogin: launchAtLogin,
            actions: StatusMenuActions(
                showWindow: { panel.show() },
                newNote: {
                    panel.show()
                    panel.handle(.newNote)
                },
                openSettings: { settings.show() },
                exportAll: { [weak self] in self?.exportAllNotes() },
                quit: { NSApp.terminate(nil) }
            ),
            showWindowShortcut: toggleWindowHotKey?.combo,
            timerCenter: timers,
            showsTimer: { [preferences] in preferences.timerInMenuBar }
        )

        applyAppearanceIfChanged()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyAppearanceIfChanged()
                self?.registerHotKeyIfChanged()
            }
        }
    }

    // MARK: Hotkey

    private func registerHotKey() {
        let combo = preferences.toggleWindowHotKey
        toggleWindowHotKey = nil // unregister the old one first
        do {
            toggleWindowHotKey = try GlobalHotKey(combo: combo) { [weak self] in self?.panelController?.toggle() }
        } catch {
            Self.logger.error("Registering hotkey \(combo.displayString, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        }
        statusItemController?.updateShortcut(toggleWindowHotKey?.combo)
    }

    /// The hotkey was changed in the settings.
    private func registerHotKeyIfChanged() {
        guard toggleWindowHotKey?.combo != preferences.toggleWindowHotKey else { return }
        registerHotKey()
    }

    // MARK: Appearance

    private func applyAppearanceIfChanged() {
        let current = (preferences.theme, preferences.fontSize, preferences.transparentWindow)
        if let applied = appliedAppearance, applied == current { return }
        appliedAppearance = current
        NSApp.appearance = switch preferences.theme {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
        panelController?.applyAppearance()
    }

    // MARK: Paste mode & export

    /// Collected clipboard text for a note that is not on screen.
    private func appendToStoredNote(noteID: String, text: String) {
        guard let store else { return }
        do {
            guard var note = try store.note(id: noteID), note.trashedAt == nil else {
                pasteCollector?.stop()
                return
            }
            note.text = PasteCollector.append(text, to: note.text)
            note.updatedAt = Date()
            note.touchedAt = note.updatedAt
            try store.save(note)
        } catch {
            Self.logger.error("Collecting clipboard text failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// All notes (except trashed and locked ones) as ZIP of Markdown files.
    func exportAllNotes() {
        guard let store else { return }
        panelController?.flush()
        let savePanel = NSSavePanel()
        savePanel.title = Strings.Export.allTitle
        savePanel.nameFieldStringValue = "Zettel-Notizen.zip"
        savePanel.allowedContentTypes = [.zip]
        NSApp.activate()
        guard savePanel.runModal() == .OK, let url = savePanel.url else { return }
        do {
            let notes = try store.allNotes()
            let count = try NoteExporter.exportAll(notes, to: url)
            let alert = NSAlert()
            alert.messageText = Strings.Export.done(count)
            if notes.contains(where: { $0.isLocked && $0.trashedAt == nil }) {
                alert.informativeText = Strings.Export.lockedNote
            }
            alert.runModal()
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = Strings.Export.failed
            alert.runModal()
        }
    }

    @objc func exportAllFromMenu() {
        exportAllNotes()
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
        updateCurrencyRatesIfDue()
    }

    /// Opt-in only: the one network access of Zettel. At most about once a day.
    private func updateCurrencyRatesIfDue() {
        guard preferences.currencyAutoUpdate, preferences.currencyRates.isUpdateDue(now: Date()) else { return }
        Task { [preferences] in
            await Self.downloadCurrencyRates(into: preferences)
        }
    }

    static func downloadCurrencyRates(into preferences: AppPreferences) async {
        do {
            let result = try await ECBReferenceRates.download()
            var rates = preferences.currencyRates
            rates.fetched = result.rates
            rates.fetchedDate = result.date
            rates.lastUpdate = Date()
            preferences.currencyRates = rates
        } catch {
            logger.error("Currency rate download failed: \(error.localizedDescription, privacy: .public)")
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
