import SwiftUI

/// Settings UI. Phase 0 only contains the login item option; later phases add
/// their options here.
struct SettingsView: View {
    @Bindable var launchAtLogin: LaunchAtLoginController
    @AppStorage(AppPreferences.Key.newNoteAfterIdleMinutes) private var newNoteAfterIdleMinutes = 0
    @AppStorage(AppPreferences.Key.checkedItemBehavior) private var checkedItemBehavior = CheckedItemBehavior.keep

    var body: some View {
        Form {
            Section(Strings.Settings.general) {
                Toggle(Strings.Settings.launchAtLogin, isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))

                if launchAtLogin.needsApproval {
                    HStack {
                        Text(Strings.Settings.needsApproval)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(Strings.Settings.openSystemSettings) {
                            launchAtLogin.openSystemSettings()
                        }
                    }
                } else if launchAtLogin.status == .notFound {
                    Text(Strings.Settings.notFound)
                        .foregroundStyle(.secondary)
                }

                if let error = launchAtLogin.lastError {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }

            Section(Strings.Settings.notes) {
                Picker(Strings.Settings.newNoteAfterIdle, selection: $newNoteAfterIdleMinutes) {
                    ForEach(FreshNotePolicy.choices, id: \.self) { minutes in
                        Text(minutes == 0 ? Strings.Settings.never : Strings.Settings.minutes(minutes))
                            .tag(minutes)
                    }
                }
                Text(Strings.Settings.newNoteAfterIdleHelp)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section(Strings.Settings.lists) {
                Picker(Strings.Settings.checkedItems, selection: $checkedItemBehavior) {
                    Text(Strings.Settings.checkedKeep).tag(CheckedItemBehavior.keep)
                    Text(Strings.Settings.checkedMoveToBottom).tag(CheckedItemBehavior.moveToBottom)
                    Text(Strings.Settings.checkedDelete).tag(CheckedItemBehavior.delete)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
