import SwiftUI

/// Settings UI. Phase 0 only contains the login item option; later phases add
/// their options here.
struct SettingsView: View {
    @Bindable var launchAtLogin: LaunchAtLoginController
    @AppStorage(AppPreferences.Key.newNoteAfterIdleMinutes) private var newNoteAfterIdleMinutes = 0

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
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
