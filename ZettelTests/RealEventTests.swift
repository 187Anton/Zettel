import AppKit
import Carbon.HIToolbox
import Testing
@testable import Zettel

/// Drives the real panel with synthesized key events through `NSApp.sendEvent`,
/// including AppKit's end-of-event undo grouping. Catches undo issues that
/// direct method calls cannot show.
@MainActor
@Suite(.serialized)
struct RealEventTests {
    private let clock = TestClock()
    private let storage = TemporaryDefaults()

    /// What `-[NSApplication run]` does after every event: close open undo groups.
    private static let endTopLevelGroupings = Selector(("_endTopLevelGroupings"))

    private func key(_ characters: String, _ keyCode: Int, _ flags: NSEvent.ModifierFlags = [], in window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: UInt16(keyCode)
        )!
    }

    private func send(_ event: NSEvent) {
        NSApp.sendEvent(event)
        if UndoManager.responds(to: Self.endTopLevelGroupings) {
            UndoManager.perform(Self.endTopLevelGroupings)
        }
    }

    private func type(_ text: String, in window: NSWindow) {
        for character in text {
            if character == "\n" {
                send(key("\r", kVK_Return, in: window))
            } else {
                send(key(String(character), kVK_ANSI_A, in: window))
            }
        }
    }

    @Test func undoAfterListContinuationKeepsTypedText() throws {
        try #require(UndoManager.responds(to: Self.endTopLevelGroupings), "AppKit internals changed; test cannot simulate events")
        let (controller, cleanup) = makeVisibleController()
        defer { cleanup() }
        let window = try #require(controller.editor.textView.window)

        type("[] Milch\n", in: window)
        #expect(controller.editor.textView.string == "☐ Milch\n☐ ")

        send(key("z", kVK_ANSI_Z, .command, in: window))
        #expect(controller.editor.textView.string == "☐ Milch")
    }

    private func makeVisibleController() -> (PanelController, () -> Void) {
        let controller = PanelController(
            preferences: AppPreferences(defaults: storage.defaults),
            notes: try! makeModel(clock: clock),
            now: clock.closure
        )
        let previousMenu = NSApp.mainMenu
        NSApp.mainMenu = MainMenu.make(settingsTarget: NSApp, settingsAction: #selector(NSApplication.terminate(_:)))
        controller.show()
        return (controller, {
            controller.hide()
            NSApp.mainMenu = previousMenu
        })
    }

    @Test func undoRightAfterAutoConversionRestoresTypedDash() throws {
        try #require(UndoManager.responds(to: Self.endTopLevelGroupings), "AppKit internals changed; test cannot simulate events")
        let controller = PanelController(
            preferences: AppPreferences(defaults: storage.defaults),
            notes: try makeModel(clock: clock),
            now: clock.closure
        )
        let previousMenu = NSApp.mainMenu
        NSApp.mainMenu = MainMenu.make(settingsTarget: NSApp, settingsAction: #selector(NSApplication.terminate(_:)))
        defer {
            controller.hide()
            NSApp.mainMenu = previousMenu
        }
        controller.show()
        let window = try #require(controller.editor.textView.window)

        send(key("-", kVK_ANSI_Minus, in: window))
        send(key(" ", kVK_Space, in: window))
        #expect(controller.editor.textView.string == "• ")

        send(key("z", kVK_ANSI_Z, .command, in: window))
        #expect(controller.editor.textView.string == "- ")
    }
}
