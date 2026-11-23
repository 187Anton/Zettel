import Observation

/// UI-independent logic for the "Beim Login starten" option.
///
/// The status is never cached as the source of truth: the user can change it in
/// System Settings at any time, so callers invoke `refresh()` right before showing
/// UI (menu opening, settings window appearing). No polling.
@MainActor
@Observable
final class LaunchAtLoginController {
    private let service: LoginItemService

    private(set) var status: LoginItemStatus
    /// Last error from register/unregister, cleared on the next successful change.
    private(set) var lastError: String?

    init(service: LoginItemService) {
        self.service = service
        self.status = service.status
    }

    /// `true` when the app is registered, even if approval is still pending.
    var isEnabled: Bool {
        status == .enabled || status == .requiresApproval
    }

    /// `true` when the user has to confirm the login item in System Settings.
    var needsApproval: Bool {
        status == .requiresApproval
    }

    func refresh() {
        status = service.status
    }

    func toggle() {
        setEnabled(!isEnabled)
    }

    func setEnabled(_ enabled: Bool) {
        refresh()
        guard enabled != isEnabled else { return }

        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }

        refresh()
        if enabled, status == .requiresApproval {
            service.openSystemSettings()
        }
    }

    func openSystemSettings() {
        service.openSystemSettings()
    }
}
