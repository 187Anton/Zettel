import AppKit
import Testing
@testable import Zettel

@MainActor
struct StatusMenuTests {
    private func makeMenu(
        status: LoginItemStatus = .disabled,
        showWindow: (@MainActor () -> Void)? = {},
        shortcut: KeyCombo? = nil,
        newNote: (@MainActor () -> Void)? = nil,
        openSettings: @escaping @MainActor () -> Void = {},
        quit: @escaping @MainActor () -> Void = {}
    ) -> (StatusMenu, FakeLoginItemService) {
        let service = FakeLoginItemService(status: status)
        let menu = StatusMenu(
            launchAtLogin: LaunchAtLoginController(service: service),
            actions: StatusMenuActions(showWindow: showWindow, newNote: newNote, openSettings: openSettings, quit: quit),
            showWindowShortcut: shortcut
        )
        return (menu, service)
    }

    @Test func showWindowItemDisplaysHotKeyAndInvokesAction() throws {
        var called = false
        let (menu, _) = makeMenu(showWindow: { called = true }, shortcut: .defaultToggleWindow)
        let item = try #require(menu.item(.showWindow))

        #expect(item.title == "Notizfenster öffnen")
        #expect(item.keyEquivalent == "a")
        #expect(item.keyEquivalentModifierMask == .option)
        #expect(item.isEnabled)

        menu.menu.performActionForItem(at: menu.menu.index(of: item))
        #expect(called)
    }

    @Test func showWindowItemWithoutHotKeyHasNoShortcut() throws {
        let (menu, _) = makeMenu(shortcut: nil)
        #expect(try #require(menu.item(.showWindow)).keyEquivalent == "")
    }

    @Test func containsAllItemsInOrder() {
        let (menu, _) = makeMenu()
        let ids = menu.menu.items.compactMap { $0.identifier?.rawValue }
        #expect(ids == StatusMenu.ItemID.allCases.map(\.rawValue))
    }

    @Test func titlesAndShortcuts() throws {
        let (menu, _) = makeMenu()

        let newNote = try #require(menu.item(.newNote))
        #expect(newNote.title == "Neue Notiz")
        #expect(newNote.keyEquivalent == "n")

        let settings = try #require(menu.item(.settings))
        #expect(settings.keyEquivalent == ",")

        let quit = try #require(menu.item(.quit))
        #expect(quit.keyEquivalent == "q")
    }

    @Test func newNoteDisabledWithoutAction() throws {
        let (menu, _) = makeMenu(newNote: nil)
        #expect(try #require(menu.item(.newNote)).isEnabled == false)
    }

    @Test func newNoteEnabledWithAction() throws {
        var called = false
        let (menu, _) = makeMenu(newNote: { called = true })
        let item = try #require(menu.item(.newNote))
        #expect(item.isEnabled)

        menu.menu.performActionForItem(at: menu.menu.index(of: item))
        #expect(called)
    }

    @Test func settingsAndQuitInvokeActions() throws {
        var settingsCalled = false
        var quitCalled = false
        let (menu, _) = makeMenu(openSettings: { settingsCalled = true }, quit: { quitCalled = true })

        menu.menu.performActionForItem(at: menu.menu.index(of: try #require(menu.item(.settings))))
        menu.menu.performActionForItem(at: menu.menu.index(of: try #require(menu.item(.quit))))

        #expect(settingsCalled)
        #expect(quitCalled)
    }

    @Test(arguments: [
        (LoginItemStatus.enabled, NSControl.StateValue.on),
        (.disabled, .off),
        (.notFound, .off),
        (.requiresApproval, .mixed),
    ])
    func loginItemCheckmarkReflectsStatus(status: LoginItemStatus, expected: NSControl.StateValue) throws {
        let (menu, _) = makeMenu(status: status)
        #expect(try #require(menu.item(.launchAtLogin)).state == expected)
    }

    @Test func clickingLoginItemTogglesRegistration() throws {
        let (menu, service) = makeMenu(status: .disabled)
        let item = try #require(menu.item(.launchAtLogin))

        menu.menu.performActionForItem(at: menu.menu.index(of: item))
        #expect(service.registerCalls == 1)
        #expect(item.state == .on)

        menu.menu.performActionForItem(at: menu.menu.index(of: item))
        #expect(service.unregisterCalls == 1)
        #expect(item.state == .off)
    }

    @Test func clickingLoginItemWhilePendingApprovalOpensSettings() throws {
        let (menu, service) = makeMenu(status: .requiresApproval)
        let item = try #require(menu.item(.launchAtLogin))

        menu.menu.performActionForItem(at: menu.menu.index(of: item))

        #expect(service.openSettingsCalls == 1)
        #expect(service.unregisterCalls == 0)
    }

    @Test func menuRefreshesStatusBeforeOpening() throws {
        let (menu, service) = makeMenu(status: .disabled)
        service.status = .enabled // changed externally in System Settings

        menu.menuNeedsUpdate(menu.menu)

        #expect(try #require(menu.item(.launchAtLogin)).state == .on)
    }
}
