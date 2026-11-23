import ServiceManagement

/// Registration state of the app as a login item.
enum LoginItemStatus: Equatable, Sendable {
    /// Registered and allowed to launch at login.
    case enabled
    /// Not registered.
    case disabled
    /// Registered, but the user must still allow it in System Settings › Login Items.
    case requiresApproval
    /// The system could not find the app's login item (e.g. app not in a valid location).
    case notFound
}

/// Abstraction over `SMAppService` so the toggle logic can be unit-tested.
@MainActor
protocol LoginItemService: AnyObject {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

/// Production implementation backed by `SMAppService.mainApp`.
@MainActor
final class SystemLoginItemService: LoginItemService {
    private var service: SMAppService { .mainApp }

    var status: LoginItemStatus {
        switch service.status {
        case .enabled: .enabled
        case .notRegistered: .disabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        @unknown default: .notFound
        }
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
