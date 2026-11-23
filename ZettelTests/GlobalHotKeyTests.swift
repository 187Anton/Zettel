import Carbon.HIToolbox
import Testing
@testable import Zettel

@MainActor
struct GlobalHotKeyTests {
    /// A combination nobody uses, so the test never collides with real shortcuts.
    private let unusualCombo = KeyCombo(keyCode: UInt32(kVK_F19), modifiers: [.control, .option, .shift, .command])

    @Test func registersWithSystem() throws {
        let hotKey = try GlobalHotKey(combo: unusualCombo) {}
        #expect(hotKey.isRegistered)
        #expect(hotKey.hotKeyID.signature == GlobalHotKey.signature)
    }

    @Test func eachHotKeyGetsItsOwnID() throws {
        let first = try GlobalHotKey(combo: unusualCombo) {}
        let second = try GlobalHotKey(combo: KeyCombo(keyCode: UInt32(kVK_F18), modifiers: unusualCombo.modifiers)) {}
        #expect(first.hotKeyID.id != second.hotKeyID.id)
    }

    @Test func matchingEventRunsAction() throws {
        var pressed = 0
        let hotKey = try GlobalHotKey(combo: unusualCombo) { pressed += 1 }

        #expect(hotKey.handle(hotKey.hotKeyID))
        #expect(pressed == 1)
    }

    @Test func foreignEventIsIgnored() throws {
        var pressed = 0
        let hotKey = try GlobalHotKey(combo: unusualCombo) { pressed += 1 }

        let otherID = EventHotKeyID(signature: hotKey.hotKeyID.signature, id: hotKey.hotKeyID.id + 1000)
        let otherSignature = EventHotKeyID(signature: 0x4142_4344, id: hotKey.hotKeyID.id)

        #expect(!hotKey.handle(otherID))
        #expect(!hotKey.handle(otherSignature))
        #expect(pressed == 0)
    }

    @Test func comboCanBeRegisteredAgainAfterRelease() throws {
        var hotKey: GlobalHotKey? = try GlobalHotKey(combo: unusualCombo) {}
        #expect(hotKey?.isRegistered == true)
        hotKey = nil

        let again = try GlobalHotKey(combo: unusualCombo) {}
        #expect(again.isRegistered)
    }
}
