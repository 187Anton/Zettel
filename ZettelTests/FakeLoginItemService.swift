@testable import Zettel

struct FakeError: Error {}

/// In-memory stand-in for `SMAppService`.
@MainActor
final class FakeLoginItemService: LoginItemService {
    var status: LoginItemStatus
    /// Status the service reports after a successful `register()`.
    var statusAfterRegister: LoginItemStatus = .enabled
    var registerError: Error?
    var unregisterError: Error?

    private(set) var registerCalls = 0
    private(set) var unregisterCalls = 0
    private(set) var openSettingsCalls = 0

    init(status: LoginItemStatus = .disabled) {
        self.status = status
    }

    func register() throws {
        registerCalls += 1
        if let registerError { throw registerError }
        status = statusAfterRegister
    }

    func unregister() throws {
        unregisterCalls += 1
        if let unregisterError { throw unregisterError }
        status = .disabled
    }

    func openSystemSettings() {
        openSettingsCalls += 1
    }
}
