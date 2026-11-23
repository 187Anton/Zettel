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
}
