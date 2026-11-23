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

    @Test func slashPickerAndMathWithRealKeys() throws {
        try #require(UndoManager.responds(to: Self.endTopLevelGroupings), "AppKit internals changed; test cannot simulate events")
        let (controller, cleanup) = makeVisibleController()
        defer { cleanup() }
        let window = try #require(controller.editor.textView.window)

        send(key("/", kVK_ANSI_Slash, in: window))
        #expect(controller.editor.textView.isShowingKeywordPicker)
        send(key("2", kVK_ANSI_2, in: window))
        #expect(controller.editor.textView.string == "math")

        type("\n6 * 7 =", in: window)
        #expect(controller.editor.textView.annotations[1]?.text == "42")

        // Esc closes an open picker but keeps the window and the "/".
        type("\n", in: window)
        send(key("/", kVK_ANSI_Slash, in: window))
        send(key("\u{1B}", kVK_Escape, in: window))
        #expect(!controller.editor.textView.isShowingKeywordPicker)
        #expect(controller.isVisible)
        #expect(controller.editor.textView.string.hasSuffix("\n/"))
    }

    @Test func commentInListWithGermanSlash() throws {
        try #require(UndoManager.responds(to: Self.endTopLevelGroupings), "AppKit internals changed; test cannot simulate events")
        let (controller, cleanup) = makeVisibleController()
        defer { cleanup() }
        let window = try #require(controller.editor.textView.window)

        type("list\nMilch\n", in: window)
        // German keyboard: "/" is ⇧7.
        send(key("/", kVK_ANSI_7, .shift, in: window))
        send(key("/", kVK_ANSI_7, .shift, in: window))
        type(" Kommentar", in: window)
        #expect(controller.editor.textView.string == "list\n☐ Milch\n// Kommentar")
        #expect(!controller.editor.textView.isShowingKeywordPicker)
    }

    @Test func searchWithRealKeys() throws {
        try #require(UndoManager.responds(to: Self.endTopLevelGroupings), "AppKit internals changed; test cannot simulate events")
        let (controller, cleanup) = makeVisibleController()
        defer { cleanup() }
        let window = try #require(controller.editor.textView.window)

        type("Notiz über Tee", in: window)
        send(key("n", kVK_ANSI_N, .command, in: window))
        type("Andere", in: window)

        send(key("f", kVK_ANSI_F, .command, in: window))
        #expect(controller.isSearching)

        // Esc closes the search, not the window.
        send(key("\u{1B}", kVK_Escape, in: window))
        #expect(!controller.isSearching)
        #expect(controller.isVisible)
    }

    @Test func escapeInFindBarKeepsWindowOpen() throws {
        try #require(UndoManager.responds(to: Self.endTopLevelGroupings), "AppKit internals changed; test cannot simulate events")
        let (controller, cleanup) = makeVisibleController()
        defer { cleanup() }
        let window = try #require(controller.editor.textView.window)
        type("Hallo Welt", in: window)

        send(key("F", kVK_ANSI_F, [.command, .shift], in: window))
        let scrollView = try #require(controller.editor.textView.enclosingScrollView)
        #expect(scrollView.isFindBarVisible)

        send(key("\u{1B}", kVK_Escape, in: window))
        #expect(controller.isVisible)
    }

    @Test func formattingWithRealKeys() throws {
        try #require(UndoManager.responds(to: Self.endTopLevelGroupings), "AppKit internals changed; test cannot simulate events")
        let (controller, cleanup) = makeVisibleController()
        defer { cleanup() }
        let window = try #require(controller.editor.textView.window)
        type("Wort", in: window)
        controller.editor.textView.selectAll(nil)

        send(key("b", kVK_ANSI_B, .command, in: window))
        #expect(controller.editor.textView.string == "**Wort**")

        // ⌘/ on a German keyboard is ⌘⇧7.
        send(key("/", kVK_ANSI_7, [.command, .shift], in: window))
        #expect(controller.editor.textView.string == "// **Wort**")

        send(key("z", kVK_ANSI_Z, .command, in: window))
        #expect(controller.editor.textView.string == "**Wort**")
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
