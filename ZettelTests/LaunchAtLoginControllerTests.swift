import Testing
@testable import Zettel

@MainActor
struct LaunchAtLoginControllerTests {
    @Test(arguments: [
        (LoginItemStatus.enabled, true),
        (.requiresApproval, true),
        (.disabled, false),
        (.notFound, false),
    ])
    func isEnabledReflectsStatus(status: LoginItemStatus, expected: Bool) {
        let controller = LaunchAtLoginController(service: FakeLoginItemService(status: status))
        #expect(controller.isEnabled == expected)
    }

    @Test func toggleFromDisabledRegisters() {
        let service = FakeLoginItemService(status: .disabled)
        let controller = LaunchAtLoginController(service: service)

        controller.toggle()

        #expect(service.registerCalls == 1)
        #expect(controller.status == .enabled)
        #expect(controller.isEnabled)
        #expect(service.openSettingsCalls == 0)
        #expect(controller.lastError == nil)
    }

    @Test func toggleFromEnabledUnregisters() {
        let service = FakeLoginItemService(status: .enabled)
        let controller = LaunchAtLoginController(service: service)

        controller.toggle()

        #expect(service.unregisterCalls == 1)
        #expect(controller.status == .disabled)
        #expect(!controller.isEnabled)
    }

    @Test func registerNeedingApprovalOpensSystemSettings() {
        let service = FakeLoginItemService(status: .disabled)
        service.statusAfterRegister = .requiresApproval
        let controller = LaunchAtLoginController(service: service)

        controller.setEnabled(true)

        #expect(controller.needsApproval)
        #expect(service.openSettingsCalls == 1)
    }

    @Test func setEnabledIsNoOpWhenAlreadyInState() {
        let service = FakeLoginItemService(status: .enabled)
        let controller = LaunchAtLoginController(service: service)

        controller.setEnabled(true)

        #expect(service.registerCalls == 0)
        #expect(service.unregisterCalls == 0)
    }

    @Test func registerFailureIsReportedAndStateUnchanged() {
        let service = FakeLoginItemService(status: .disabled)
        service.registerError = FakeError()
        let controller = LaunchAtLoginController(service: service)

        controller.setEnabled(true)

        #expect(controller.status == .disabled)
        #expect(controller.lastError != nil)
    }

    @Test func successfulChangeClearsPreviousError() {
        let service = FakeLoginItemService(status: .disabled)
        service.registerError = FakeError()
        let controller = LaunchAtLoginController(service: service)
        controller.setEnabled(true)
        #expect(controller.lastError != nil)

        service.registerError = nil
        controller.setEnabled(true)

        #expect(controller.lastError == nil)
        #expect(controller.status == .enabled)
    }

    @Test func refreshPicksUpExternalChanges() {
        let service = FakeLoginItemService(status: .enabled)
        let controller = LaunchAtLoginController(service: service)

        // User disables the login item in System Settings.
        service.status = .disabled
        #expect(controller.isEnabled)

        controller.refresh()
        #expect(!controller.isEnabled)
    }
}
