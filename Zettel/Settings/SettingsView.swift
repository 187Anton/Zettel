import AppKit
import SwiftUI

/// The tabs of the settings window, shown as toolbar items (standard macOS style).
enum SettingsTab: CaseIterable {
    case general, notes, math, timer, backups

    var title: String {
        switch self {
        case .general: Strings.Settings.general
        case .notes: Strings.Settings.notes
        case .math: Strings.Settings.listsAndMath
        case .timer: Strings.Settings.timer
        case .backups: Strings.Settings.backups
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .notes: "note.text"
        case .math: "function"
        case .timer: "timer"
        case .backups: "externaldrive"
        }
    }

    /// Content height; the window adapts when switching tabs.
    var height: CGFloat {
        switch self {
        case .general: 120
        case .notes: 380
        case .math: 380
        case .timer: 250
        case .backups: 440
        }
    }

    static let width: CGFloat = 520

    @MainActor
    func view(launchAtLogin: LaunchAtLoginController, backups: BackupManager?, onRestore: @escaping () -> Void) -> AnyView {
        let content: AnyView = switch self {
        case .general: AnyView(GeneralSettings(launchAtLogin: launchAtLogin))
        case .notes: AnyView(NotesSettings())
        case .math: AnyView(MathSettings())
        case .timer: AnyView(TimerSettings())
        case .backups: AnyView(BackupSettings(backups: backups, onRestore: onRestore))
        }
        return AnyView(content.frame(width: Self.width, height: height))
    }
}

// MARK: - Tabs

private struct GeneralSettings: View {
    @Bindable var launchAtLogin: LaunchAtLoginController

    var body: some View {
        Form {
            Section {
                Toggle(Strings.Settings.launchAtLogin, isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                if launchAtLogin.needsApproval {
                    HStack {
                        Text(Strings.Settings.needsApproval).foregroundStyle(.secondary)
                        Spacer()
                        Button(Strings.Settings.openSystemSettings) { launchAtLogin.openSystemSettings() }
                    }
                } else if launchAtLogin.status == .notFound {
                    Text(Strings.Settings.notFound).foregroundStyle(.secondary)
                }
                if let error = launchAtLogin.lastError {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct NotesSettings: View {
    @AppStorage(AppPreferences.Key.newNoteAfterIdleMinutes) private var newNoteAfterIdleMinutes = 0
    @AppStorage(AppPreferences.Key.noteExpiry) private var expiry = NoteRetention.Expiry.never
    @AppStorage(AppPreferences.Key.trashPeriod) private var trashPeriod = NoteRetention.TrashPeriod.days30
    @AppStorage(AppPreferences.Key.slotShortcuts) private var slotShortcuts = false

    var body: some View {
        Form {
            Section {
                Picker(Strings.Settings.newNoteAfterIdle, selection: $newNoteAfterIdleMinutes) {
                    ForEach(FreshNotePolicy.choices, id: \.self) { minutes in
                        Text(minutes == 0 ? Strings.Settings.never : Strings.Settings.minutes(minutes)).tag(minutes)
                    }
                }
                Text(Strings.Settings.newNoteAfterIdleHelp).font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Picker(Strings.Settings.expiry, selection: $expiry) {
                    ForEach(NoteRetention.Expiry.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker(Strings.Settings.trashPeriod, selection: $trashPeriod) {
                    ForEach(NoteRetention.TrashPeriod.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Text(Strings.Settings.retentionHelp).font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Toggle(Strings.Settings.slotShortcuts, isOn: $slotShortcuts)
                Text(Strings.Settings.slotShortcutsHelp).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct MathSettings: View {
    @AppStorage(AppPreferences.Key.checkedItemBehavior) private var checkedItemBehavior = CheckedItemBehavior.keep
    @AppStorage(AppPreferences.Key.mathDecimals) private var mathDecimals = -1
    @AppStorage(AppPreferences.Key.mathDecimalSeparator) private var decimalSeparator = String(NumberStyle.system.decimalSeparator)
    @AppStorage(AppPreferences.Key.mathGroupingSeparator) private var groupingSeparator = NumberStyle.system.groupingSeparator.map(String.init) ?? "none"

    private var previewStyle: NumberStyle {
        NumberStyle(
            decimalSeparator: decimalSeparator.first ?? ",",
            groupingSeparator: groupingSeparator == "none" ? nil : groupingSeparator.first,
            decimals: mathDecimals < 0 ? nil : mathDecimals
        )
    }

    var body: some View {
        Form {
            Section(Strings.Settings.lists) {
                Picker(Strings.Settings.checkedItems, selection: $checkedItemBehavior) {
                    Text(Strings.Settings.checkedKeep).tag(CheckedItemBehavior.keep)
                    Text(Strings.Settings.checkedMoveToBottom).tag(CheckedItemBehavior.moveToBottom)
                    Text(Strings.Settings.checkedDelete).tag(CheckedItemBehavior.delete)
                }
            }
            Section(Strings.Settings.math) {
                Picker(Strings.Settings.decimals, selection: $mathDecimals) {
                    Text(Strings.Settings.decimalsAutomatic).tag(-1)
                    ForEach(0...6, id: \.self) { Text("\($0)").tag($0) }
                }
                Picker(Strings.Settings.decimalSeparator, selection: $decimalSeparator) {
                    Text(Strings.Settings.comma).tag(",")
                    Text(Strings.Settings.period).tag(".")
                }
                Picker(Strings.Settings.groupingSeparator, selection: $groupingSeparator) {
                    Text(Strings.Settings.none).tag("none")
                    Text(Strings.Settings.period).tag(".")
                    Text(Strings.Settings.comma).tag(",")
                    Text(Strings.Settings.space).tag(" ")
                    Text(Strings.Settings.apostrophe).tag("'")
                }
                LabeledContent(Strings.Settings.example) {
                    Text(previewStyle.format(1234567.891)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct TimerSettings: View {
    @AppStorage(AppPreferences.Key.timerNotifications) private var timerNotifications = true
    @AppStorage(AppPreferences.Key.timerSound) private var timerSound = true
    @AppStorage(AppPreferences.Key.timerSoundName) private var timerSoundName = "Glass"
    @AppStorage(AppPreferences.Key.timerInMenuBar) private var timerInMenuBar = true

    var body: some View {
        Form {
            Section {
                Toggle(Strings.Settings.timerNotifications, isOn: $timerNotifications)
                Toggle(Strings.Settings.timerSound, isOn: $timerSound)
                Picker(Strings.Settings.timerSoundName, selection: $timerSoundName) {
                    ForEach(TimerAlerts.sounds, id: \.self) { Text($0).tag($0) }
                }
                .disabled(!timerSound)
                .onChange(of: timerSoundName) { _, name in NSSound(named: NSSound.Name(name))?.play() }
                Toggle(Strings.Settings.timerInMenuBar, isOn: $timerInMenuBar)
            }
        }
        .formStyle(.grouped)
    }
}

private struct BackupSettings: View {
    let backups: BackupManager?
    let onRestore: () -> Void

    @AppStorage(AppPreferences.Key.backupInterval) private var interval = BackupManager.Interval.daily
    @State private var list: [BackupManager.Backup] = []
    @State private var pendingRestore: BackupManager.Backup?
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                Picker(Strings.Settings.backupInterval, selection: $interval) {
                    ForEach(BackupManager.Interval.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Text(Strings.Settings.backupHelp).font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                if list.isEmpty {
                    Text(Strings.Settings.noBackups).foregroundStyle(.secondary)
                }
                ForEach(list) { backup in
                    HStack {
                        Text(backup.date, format: .dateTime.day().month().year().hour().minute())
                        Text(ByteCountFormatter.string(fromByteCount: backup.size, countStyle: .file))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(Strings.Settings.restoreBackup) { pendingRestore = backup }
                    }
                }
                HStack {
                    Button(Strings.Settings.backupNow) {
                        run { _ = try backups?.createBackup() }
                    }
                    Button(Strings.Settings.showInFinder) {
                        if let directory = backups?.directory {
                            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                            NSWorkspace.shared.activateFileViewerSelecting([directory])
                        }
                    }
                }
                if let message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: reload)
        .alert(
            Strings.Settings.restoreQuestion,
            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
            presenting: pendingRestore
        ) { backup in
            Button(Strings.Settings.restoreBackup, role: .destructive) {
                run {
                    try backups?.restore(backup)
                    onRestore()
                    message = Strings.Settings.restored
                }
            }
            Button(Strings.Settings.cancel, role: .cancel) {}
        } message: { _ in
            Text(Strings.Settings.restoreExplanation)
        }
    }

    private func reload() {
        list = backups?.backups() ?? []
    }

    private func run(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            message = error.localizedDescription
        }
        reload()
    }
}
