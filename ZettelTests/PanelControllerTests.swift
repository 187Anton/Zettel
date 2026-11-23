import AppKit
import Testing
@testable import Zettel

/// Exercises the real panel inside the test host. Focus (key window) behavior
/// depends on the window server and is covered by `PanelVisibilityTests` instead.
@MainActor
@Suite(.serialized)
struct PanelControllerTests {
    private let storage = TemporaryDefaults()

    private let clock = TestClock()

    private func makeController(store: NoteStore? = nil) throws -> (PanelController, AppPreferences) {
        let preferences = AppPreferences(defaults: storage.defaults)
        let notes = try makeModel(store: store, clock: clock)
        return (PanelController(preferences: preferences, notes: notes, now: clock.closure), preferences)
    }

    @Test func startsHiddenAndUnpinned() throws {
        let (controller, _) = try makeController()
        #expect(!controller.isVisible)
        #expect(!controller.isPinned)
    }

    @Test func showAndCloseCommand() throws {
        let (controller, _) = try makeController()

        controller.show()
        #expect(controller.isVisible)

        controller.handle(.close)
        #expect(!controller.isVisible)
    }

    @Test func pinStateIsPersisted() throws {
        let (controller, preferences) = try makeController()

        controller.handle(.togglePin)
        #expect(controller.isPinned)
        #expect(preferences.isPanelPinned)

        let (restored, _) = try makeController()
        #expect(restored.isPinned)

        restored.togglePin()
        #expect(!preferences.isPanelPinned)
    }

    @Test func frameIsSavedOnHideAndRestored() throws {
        let screen = try #require(NSScreen.main?.visibleFrame)
        let (controller, preferences) = try makeController()
        let frame = NSRect(x: screen.minX + 40, y: screen.minY + 40, width: 360, height: 300)
        preferences.panelFrame = frame

        controller.show()
        #expect(controller.frame == frame)
        controller.hide()

        let (restored, _) = try makeController()
        restored.show()
        #expect(restored.frame == frame)
        restored.hide()
    }

    @Test func firstShowUsesDefaultSize() throws {
        let (controller, preferences) = try makeController()
        controller.show()
        #expect(controller.frame?.size == PanelFramePlacement.defaultSize)
        controller.hide()
        #expect(preferences.panelFrame?.size == PanelFramePlacement.defaultSize)
    }

    @Test func showFocusesTheEditor() throws {
        let (controller, _) = try makeController()
        controller.show()
        defer { controller.hide() }
        #expect(controller.editor.textView.window != nil)
    }

    @Test func noteCommandsReachTheEditor() throws {
        let (controller, _) = try makeController()
        controller.show()
        defer { controller.hide() }
        controller.editor.textView.insertText("Text", replacementRange: NSRange(location: 0, length: 0))

        controller.handle(.newNote)

        #expect(controller.editor.model.count == 2)
        #expect(controller.editor.textView.string == "")
    }

    @Test func hideSavesPendingText() throws {
        let store = try NoteStore.inMemory()
        let (controller, _) = try makeController(store: store)
        controller.show()
        controller.editor.textView.insertText("Nicht verlieren", replacementRange: NSRange(location: 0, length: 0))

        controller.hide()

        #expect(try store.stack().first?.text == "Nicht verlieren")
    }

    @Test func opensWithFreshNoteAfterIdleTime() throws {
        let (controller, preferences) = try makeController()
        preferences.newNoteAfterIdleMinutes = 5
        controller.show()
        controller.editor.textView.insertText("Alt", replacementRange: NSRange(location: 0, length: 0))
        controller.hide()

        clock.advance(seconds: 4 * 60)
        controller.show()
        #expect(controller.editor.textView.string == "Alt")
        controller.hide()

        clock.advance(seconds: 5 * 60)
        controller.show()
        #expect(controller.editor.textView.string == "")
        #expect(controller.editor.model.count == 2)
        controller.hide()
    }

    @Test func searchOpensAndEscapeClosesItFirst() throws {
        let (controller, _) = try makeController()
        controller.show()
        defer { controller.hide() }

        controller.handle(.search)
        #expect(controller.isSearching)

        controller.handle(.close) // Esc
        #expect(!controller.isSearching)
        #expect(controller.isVisible)

        controller.handle(.close)
        #expect(!controller.isVisible)
    }

    @Test func searchResultOpensNote() throws {
        let store = try NoteStore.inMemory()
        let (controller, _) = try makeController(store: store)
        controller.loadAllNotes = { (try? store.allNotes()) ?? [] }
        controller.show()
        defer { controller.hide() }
        controller.editor.textView.insertText("Erste Notiz über Kaffee", replacementRange: NSRange(location: NSNotFound, length: 0))
        controller.handle(.newNote)
        controller.editor.textView.insertText("Zweite", replacementRange: NSRange(location: NSNotFound, length: 0))

        controller.handle(.search)
        let model = try #require(controller.currentSearchModel)
        model.query = "kaffee"
        #expect(model.results.count == 1)
        model.activateSelection()

        #expect(!controller.isSearching)
        #expect(controller.editor.textView.string == "Erste Notiz über Kaffee")
    }

    @Test func numberKeysFollowMode() throws {
        let (controller, preferences) = try makeController()
        controller.show()
        defer { controller.hide() }

        controller.handle(.number(3))
        #expect(controller.editor.model.mode == .stack)

        controller.handle(.toggleSlots)
        controller.handle(.number(3))
        #expect(controller.editor.model.mode == .slot(3))

        controller.handle(.toggleSlots)
        preferences.slotShortcuts = true
        controller.handle(.number(5))
        #expect(controller.editor.model.mode == .slot(5))
    }

    /// Renders the search view (see `EditorViewControllerTests.snapshot`).
    @Test func snapshotSearch() throws {
        guard ProcessInfo.processInfo.environment["ZETTEL_SNAPSHOT"] == "1" else { return }
        let store = try NoteStore.inMemory()
        let texts = [
            "list: Einkauf\n- [ ] Hafermilch\n- [x] Brot",
            "math: Urlaub\nflug : 420\nhotel : 7 * 95\nflug + hotel =",
            "Idee für den Vortrag: mit einer Geschichte anfangen, dann Zahlen",
            "Telefonnummer Handwerker 0171 1234567",
        ]
        for (index, text) in texts.enumerated() {
            var note = Note(text: text, date: clock.now.addingTimeInterval(Double(index) * -3600), slot: index == 1 ? 2 : nil)
            if index == 3 { note.archivedAt = clock.now }
            try store.insert(note)
        }
        let (controller, _) = try makeController(store: store)
        controller.loadAllNotes = { (try? store.allNotes()) ?? [] }
        controller.show()
        defer { controller.hide() }
        controller.handle(.search)
        let window = try #require(controller.editor.view.window)
        window.appearance = NSAppearance(named: .aqua)
        let view = try #require(window.contentView)
        view.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("search.png")
        try rep.representation(using: .png, properties: [:])?.write(to: url)
        print("SNAPSHOT \(url.path)")
    }
}
