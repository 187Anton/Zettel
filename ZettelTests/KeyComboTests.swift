import Carbon.HIToolbox
import Foundation
import Testing
@testable import Zettel

struct KeyComboTests {
    @Test func defaultToggleWindowIsOptionA() {
        let combo = KeyCombo.defaultToggleWindow
        #expect(combo.keyCode == UInt32(kVK_ANSI_A))
        #expect(combo.modifiers == .option)
        #expect(combo.displayString == "⌥A")
    }

    @Test(arguments: [
        (KeyModifiers.command, cmdKey),
        (.option, optionKey),
        (.control, controlKey),
        (.shift, shiftKey),
    ])
    func carbonFlagsForSingleModifier(modifier: KeyModifiers, expected: Int) {
        #expect(modifier.carbonFlags == UInt32(expected))
    }

    @Test func carbonFlagsCombine() {
        let modifiers: KeyModifiers = [.command, .shift]
        #expect(modifiers.carbonFlags == UInt32(cmdKey | shiftKey))
        #expect(KeyModifiers().carbonFlags == 0)
    }

    @Test func symbolsUseSystemOrder() {
        let all: KeyModifiers = [.command, .shift, .option, .control]
        #expect(all.symbols == "⌃⌥⇧⌘")
    }

    @Test func displayStringForOtherKeys() {
        #expect(KeyCombo(keyCode: UInt32(kVK_ANSI_5), modifiers: [.command, .shift]).displayString == "⇧⌘5")
        #expect(KeyCombo(keyCode: UInt32(kVK_Space), modifiers: .control).displayString == "⌃Space")
        #expect(KeyCombo(keyCode: UInt32(kVK_F19), modifiers: []).displayString == "#\(kVK_F19)")
    }

    @Test func codableRoundTrip() throws {
        let combo = KeyCombo(keyCode: UInt32(kVK_ANSI_Z), modifiers: [.control, .option])
        let data = try JSONEncoder().encode(combo)
        #expect(try JSONDecoder().decode(KeyCombo.self, from: data) == combo)
    }
}
