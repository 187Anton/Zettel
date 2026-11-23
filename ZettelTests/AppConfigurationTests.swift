import Foundation
import Testing
@testable import Zettel

/// Guards the Info.plist settings the app's core requirements depend on.
/// Tests run hosted in the app, so `Bundle.main` is Zettel.app.
struct AppConfigurationTests {
    @Test func isAgentAppWithoutDockIcon() {
        let value = Bundle.main.object(forInfoDictionaryKey: "LSUIElement")
        #expect((value as? Bool) == true || (value as? String) == "1" || (value as? String) == "YES")
    }

    @Test func deploymentTargetIsSonoma() {
        let value = Bundle.main.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String
        #expect(value == "14.0")
    }
}
