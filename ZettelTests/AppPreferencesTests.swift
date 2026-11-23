import Carbon.HIToolbox
import CoreGraphics
import Foundation
import Testing
@testable import Zettel

/// Provides an isolated, throw-away `UserDefaults` suite per test.
@MainActor
final class TemporaryDefaults {
    let suiteName = "dev.zettel.tests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }
}

@MainActor
struct AppPreferencesTests {
    private let storage = TemporaryDefaults()

    @Test func defaultsWhenNothingStored() {
        let preferences = AppPreferences(defaults: storage.defaults)
        #expect(preferences.toggleWindowHotKey == .defaultToggleWindow)
        #expect(preferences.isPanelPinned == false)
        #expect(preferences.panelFrame == nil)
    }

    @Test func valuesPersistAcrossInstances() {
        let first = AppPreferences(defaults: storage.defaults)
        let combo = KeyCombo(keyCode: UInt32(kVK_ANSI_N), modifiers: [.control, .option])
        first.toggleWindowHotKey = combo
        first.isPanelPinned = true
        first.panelFrame = CGRect(x: 10.5, y: 20, width: 400, height: 300)

        let second = AppPreferences(defaults: storage.defaults)
        #expect(second.toggleWindowHotKey == combo)
        #expect(second.isPanelPinned)
        #expect(second.panelFrame == CGRect(x: 10.5, y: 20, width: 400, height: 300))
    }

    @Test func clearingFrameRemovesIt() {
        let preferences = AppPreferences(defaults: storage.defaults)
        preferences.panelFrame = CGRect(x: 0, y: 0, width: 400, height: 300)
        preferences.panelFrame = nil
        #expect(preferences.panelFrame == nil)
    }

    @Test func corruptValuesFallBackToDefaults() {
        storage.defaults.set(Data("nonsense".utf8), forKey: "hotKey.toggleWindow")
        storage.defaults.set([1.0, 2.0], forKey: "panel.frame")
        let preferences = AppPreferences(defaults: storage.defaults)
        #expect(preferences.toggleWindowHotKey == .defaultToggleWindow)
        #expect(preferences.panelFrame == nil)
    }

    @Test func emptyFrameIsIgnored() {
        storage.defaults.set([0.0, 0.0, 0.0, 0.0], forKey: "panel.frame")
        #expect(AppPreferences(defaults: storage.defaults).panelFrame == nil)
    }
}
