import Carbon.HIToolbox
import CoreGraphics
import Testing
@testable import Zettel

struct PanelShortcutsTests {
    private func command(_ keyCode: Int, _ characters: String?, ignoring: String? = nil, _ modifiers: KeyModifiers) -> PanelCommand? {
        PanelShortcuts.command(
            keyCode: UInt16(keyCode),
            characters: characters,
            charactersIgnoringModifiers: ignoring ?? characters,
            modifiers: modifiers
        )
    }

    @Test func escapeCloses() {
        #expect(command(kVK_Escape, "\u{1B}", []) == .close)
        #expect(command(kVK_Escape, "\u{1B}", .command) == nil)
    }

    @Test(arguments: [
        ("p", PanelCommand.togglePin),
        ("w", .close),
        ("n", .newNote),
        ("d", .trash),
    ])
    func commandLetters(letter: String, expected: PanelCommand) {
        #expect(command(kVK_ANSI_A, letter, .command) == expected)
    }

    @Test func bracketsNavigateOnUSLayout() {
        #expect(command(kVK_ANSI_LeftBracket, "[", .command) == .showOlder)
        #expect(command(kVK_ANSI_RightBracket, "]", .command) == .showNewer)
    }

    @Test func bracketsNavigateOnGermanLayout() {
        // ⌘⌥5 / ⌘⌥6 type "[" / "]" on a German keyboard.
        #expect(command(kVK_ANSI_5, "[", ignoring: "5", [.command, .option]) == .showOlder)
        #expect(command(kVK_ANSI_6, "]", ignoring: "6", [.command, .option]) == .showNewer)
    }

    @Test func optionCommandArrowsNavigate() {
        #expect(command(kVK_LeftArrow, "\u{F702}", [.command, .option]) == .showOlder)
        #expect(command(kVK_RightArrow, "\u{F703}", [.command, .option]) == .showNewer)
        #expect(command(kVK_LeftArrow, "\u{F702}", .command) == nil) // line start in the editor
    }

    @Test func digitOneByKeyCode() {
        #expect(command(kVK_ANSI_1, "1", .command) == .showNewest)
        #expect(command(kVK_ANSI_1, "!", [.command, .shift]) == .bringToFront)
    }

    @Test func extraModifiersDoNotMatch() {
        #expect(command(kVK_ANSI_P, "P", [.command, .shift]) == nil)
        #expect(command(kVK_ANSI_P, "π", ignoring: "p", [.command, .option]) == nil)
        #expect(command(kVK_ANSI_N, "n", [.command, .control]) == nil)
    }

    @Test func plainLettersAndEditingShortcutsAreNotPanelCommands() {
        #expect(command(kVK_ANSI_P, "p", []) == nil)
        #expect(command(kVK_ANSI_Z, "z", .command) == nil)
        #expect(command(kVK_ANSI_C, "c", .command) == nil)
    }
}

struct PanelVisibilityTests {
    @Test(arguments: [
        (false, false, PanelVisibility.Action.show),
        (true, false, .show), // pinned, focus elsewhere → bring focus back
        (true, true, .hide),
    ])
    func hotKeyAction(isVisible: Bool, isKey: Bool, expected: PanelVisibility.Action) {
        #expect(PanelVisibility.hotKeyAction(isVisible: isVisible, isKey: isKey) == expected)
    }

    @Test func hidesOnFocusLossOnlyWhenUnpinned() {
        #expect(PanelVisibility.shouldHideOnFocusLoss(isPinned: false))
        #expect(!PanelVisibility.shouldHideOnFocusLoss(isPinned: true))
    }
}

struct PanelFramePlacementTests {
    private let main = CGRect(x: 0, y: 0, width: 1440, height: 875)
    private let right = CGRect(x: 1440, y: 0, width: 1920, height: 1055)

    @Test func usesDefaultFrameWithoutSavedFrame() {
        let frame = PanelFramePlacement.frame(saved: nil, screens: [main], preferredScreen: main)
        #expect(frame.size == PanelFramePlacement.defaultSize)
        #expect(frame.midX == main.midX)
        #expect(frame.midY > main.midY) // slightly above center
        #expect(main.contains(frame))
    }

    @Test func defaultFrameShrinksOnTinyScreen() {
        let tiny = CGRect(x: 0, y: 0, width: 300, height: 250)
        let frame = PanelFramePlacement.defaultFrame(on: tiny)
        #expect(tiny.contains(frame))
        #expect(frame.width == 300)
    }

    @Test func keepsSavedFrameThatFitsOnScreen() {
        let saved = CGRect(x: 100, y: 120, width: 500, height: 400)
        #expect(PanelFramePlacement.frame(saved: saved, screens: [main], preferredScreen: main) == saved)
    }

    @Test func keepsSavedFrameOnSecondScreen() {
        let saved = CGRect(x: 2000, y: 300, width: 500, height: 400)
        #expect(PanelFramePlacement.frame(saved: saved, screens: [main, right], preferredScreen: main) == saved)
    }

    @Test func fallsBackToDefaultWhenScreenIsGone() {
        let saved = CGRect(x: 2000, y: 300, width: 500, height: 400) // was on `right`
        let frame = PanelFramePlacement.frame(saved: saved, screens: [main], preferredScreen: main)
        #expect(frame == PanelFramePlacement.defaultFrame(on: main))
    }

    @Test func movesPartiallyOffscreenFrameBackOnScreen() {
        let saved = CGRect(x: 1200, y: 600, width: 500, height: 400) // sticks out right and top
        let frame = PanelFramePlacement.frame(saved: saved, screens: [main], preferredScreen: main)
        #expect(frame.size == saved.size)
        #expect(main.contains(frame))
    }

    @Test func shrinksFrameLargerThanScreen() {
        let saved = CGRect(x: 0, y: 0, width: 3000, height: 2000)
        let frame = PanelFramePlacement.frame(saved: saved, screens: [main], preferredScreen: main)
        #expect(frame == main)
    }

    @Test func enforcesMinimumSize() {
        let saved = CGRect(x: 100, y: 100, width: 50, height: 40)
        let frame = PanelFramePlacement.frame(saved: saved, screens: [main], preferredScreen: main)
        #expect(frame.size == PanelFramePlacement.minimumSize)
    }

    @Test func barelyVisibleFrameIsReset() {
        let saved = CGRect(x: 1430, y: 100, width: 500, height: 400) // only 10 pt overlap
        #expect(PanelFramePlacement.restoredFrame(saved: saved, screens: [main]) == nil)
    }
}
