@testable import Earshot
import XCTest

@MainActor
final class AdvancedSettingsPermissionDetailTests: XCTestCase {
    /// A grant macOS reports that the probe found not working says so, and
    /// how to fix it, instead of "Granted".
    func testABrokenGrantIsNotShownAsGranted() {
        XCTAssertEqual(
            AdvancedSettingsView.detail(.broken, whenHealthy: "Granted"),
            "Allowed, but not working: switch it off and on in System Settings",
        )
        XCTAssertEqual(AdvancedSettingsView.detail(.healthy, whenHealthy: "Granted"), "Granted")
        XCTAssertEqual(AdvancedSettingsView.detail(nil, whenHealthy: "Granted"), "Checking…")
    }
}
