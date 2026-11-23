import Carbon.HIToolbox
import CoreGraphics
import Testing
@testable import Zettel

struct PanelShortcutsTests {
    private let escape = UInt16(kVK_Escape)
    private let keyP = UInt16(kVK_ANSI_P)
    private let keyW = UInt16(kVK_ANSI_W)

    @Test func escapeCloses() {
        #expect(PanelShortcuts.command(keyCode: escape, characters: "\u{1B}", modifiers: []) == .close)
    }

    @Test func escapeWithModifierIsIgnored() {
        #expect(PanelShortcuts.command(keyCode: escape, characters: "\u{1B}", modifiers: .command) == nil)
    }

    @Test func commandPTogglesPin() {
        #expect(PanelShortcuts.command(keyCode: keyP, characters: "p", modifiers: .command) == .togglePin)
    }

    @Test func commandWCloses() {
        #expect(PanelShortcuts.command(keyCode: keyW, characters: "w", modifiers: .command) == .close)
    }

    @Test func extraModifiersDoNotMatch() {
        #expect(PanelShortcuts.command(keyCode: keyP, characters: "P", modifiers: [.command, .shift]) == nil)
        #expect(PanelShortcuts.command(keyCode: keyP, characters: "p", modifiers: [.command, .option]) == nil)
    }

    @Test func plainLettersAreNotCommands() {
        #expect(PanelShortcuts.command(keyCode: keyP, characters: "p", modifiers: []) == nil)
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
