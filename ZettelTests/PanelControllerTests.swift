import AppKit
import Testing
@testable import Zettel

/// Exercises the real panel inside the test host. Focus (key window) behavior
/// depends on the window server and is covered by `PanelVisibilityTests` instead.
@MainActor
@Suite(.serialized)
struct PanelControllerTests {
    private let storage = TemporaryDefaults()

    private func makeController() -> (PanelController, AppPreferences) {
        let preferences = AppPreferences(defaults: storage.defaults)
        return (PanelController(preferences: preferences), preferences)
    }

    @Test func startsHiddenAndUnpinned() {
        let (controller, _) = makeController()
        #expect(!controller.isVisible)
        #expect(!controller.isPinned)
    }

    @Test func showAndCloseCommand() {
        let (controller, _) = makeController()

        controller.show()
        #expect(controller.isVisible)

        controller.handle(.close)
        #expect(!controller.isVisible)
    }

    @Test func pinStateIsPersisted() {
        let (controller, preferences) = makeController()

        controller.handle(.togglePin)
        #expect(controller.isPinned)
        #expect(preferences.isPanelPinned)

        let (restored, _) = makeController()
        #expect(restored.isPinned)

        restored.togglePin()
        #expect(!preferences.isPanelPinned)
    }

    @Test func frameIsSavedOnHideAndRestored() throws {
        let screen = try #require(NSScreen.main?.visibleFrame)
        let (controller, preferences) = makeController()
        let frame = NSRect(x: screen.minX + 40, y: screen.minY + 40, width: 360, height: 300)
        preferences.panelFrame = frame

        controller.show()
        #expect(controller.frame == frame)
        controller.hide()

        let (restored, _) = makeController()
        restored.show()
        #expect(restored.frame == frame)
        restored.hide()
    }

    @Test func firstShowUsesDefaultSize() {
        let (controller, preferences) = makeController()
        controller.show()
        #expect(controller.frame?.size == PanelFramePlacement.defaultSize)
        controller.hide()
        #expect(preferences.panelFrame?.size == PanelFramePlacement.defaultSize)
    }
}
