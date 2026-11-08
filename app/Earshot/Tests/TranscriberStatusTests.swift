@testable import Earshot
import XCTest

final class TranscriberStatusTests: XCTestCase {
    // MARK: - State Labels

    func testIdleLabel() {
        XCTAssertEqual(TranscriberState.idle.label, "Idle")
    }

    func testWatchingLabel() {
        XCTAssertEqual(TranscriberState.watching.label, "Watching for meetings…")
    }

    func testRecordingLabel() {
        XCTAssertEqual(TranscriberState.recording.label, "Recording")
    }

    func testErrorLabel() {
        XCTAssertEqual(TranscriberState.error.label, "Error")
    }
}
