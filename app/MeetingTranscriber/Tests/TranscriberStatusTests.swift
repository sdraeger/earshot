@testable import MeetingTranscriber
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

    // MARK: - State Icons

    func testIdleIcon() {
        XCTAssertEqual(TranscriberState.idle.icon, "waveform.circle")
    }

    func testWatchingIcon() {
        XCTAssertEqual(TranscriberState.watching.icon, "eye.fill")
    }

    func testRecordingIcon() {
        XCTAssertEqual(TranscriberState.recording.icon, "record.circle.fill")
    }

    func testErrorIcon() {
        XCTAssertEqual(TranscriberState.error.icon, "exclamationmark.triangle.fill")
    }
}
