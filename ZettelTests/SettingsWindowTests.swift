import AppKit
import Testing
@testable import Zettel

@MainActor
@Suite(.serialized)
struct SettingsWindowTests {
    @Test func hasToolbarTabsAndResizesPerTab() throws {
        let controller = SettingsWindowController(launchAtLogin: LaunchAtLoginController(service: FakeLoginItemService()))
        controller.show()
        defer { controller.close() }
        let window = try #require(controller.currentWindow)
        let tabs = try #require(window.contentViewController as? NSTabViewController)

        #expect(tabs.tabStyle == .toolbar)
        #expect(tabs.tabViewItems.map(\.label) == SettingsTab.allCases.map(\.title))

        var heights: [CGFloat] = []
        for index in tabs.tabViewItems.indices {
            tabs.selectedTabViewItemIndex = index
            window.layoutIfNeeded()
            heights.append(window.contentLayoutRect.height)
            if ProcessInfo.processInfo.environment["ZETTEL_SNAPSHOT"] == "1" {
                try snapshot(window, name: "settings-\(index).png")
            }
        }
        #expect(Set(heights).count > 1) // the window adapts to the tab
    }

    /// Renders the whole window including title bar and toolbar.
    private func snapshot(_ window: NSWindow, name: String) throws {
        window.appearance = NSAppearance(named: .darkAqua)
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        let frameView = try #require(window.contentView?.superview)
        let rep = try #require(frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds))
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try rep.representation(using: .png, properties: [:])?.write(to: url)
        print("SNAPSHOT \(url.path)")
    }
}
