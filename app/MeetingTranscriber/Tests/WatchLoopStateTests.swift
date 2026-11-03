@testable import MeetingTranscriber
import XCTest

/// Coverage for the `WatchLoopState` snapshot value type and the
/// `WatchLoop.snapshot` getter that bundles the five observable fields.
@MainActor
final class WatchLoopStateTests: XCTestCase {
    // MARK: - Equatable / initial

    func testInitialMatchesFreshLoopSnapshot() {
        let (loop, _) = makeTestWatchLoop()
        XCTAssertEqual(loop.snapshot, .initial)
    }

    func testInitialIsIdle() {
        XCTAssertEqual(WatchLoopState.initial.phase, .idle)
        XCTAssertNil(WatchLoopState.initial.currentMeeting)
        XCTAssertNil(WatchLoopState.initial.lastError)
        XCTAssertNil(WatchLoopState.initial.manualRecordingInfo)
    }

    func testEqualityRequiresAllFieldsToMatch() {
        let a = WatchLoopState.initial
        var b = WatchLoopState.initial
        XCTAssertEqual(a, b)

        b.lastError = "boom"
        XCTAssertNotEqual(a, b, "Snapshots with different errors must not compare equal")
    }

    // MARK: - Snapshot reflects live fields

    func testSnapshotReflectsPhaseTransition() {
        let (loop, _) = makeTestWatchLoop()
        XCTAssertEqual(loop.snapshot.phase, .idle)

        loop.start()
        XCTAssertEqual(loop.snapshot.phase, .watching)

        loop.stop()
        XCTAssertEqual(loop.snapshot.phase, .idle)
    }

    func testSnapshotReflectsManualRecordingInfo() async throws {
        let (loop, _) = makeTestWatchLoop()
        try await loop.startManualRecording(pid: 42, appName: "Chrome", title: "Sync")
        defer { loop.stop() }

        let info = try XCTUnwrap(loop.snapshot.manualRecordingInfo)
        XCTAssertEqual(info, ManualRecordingInfo(pid: 42, appName: "Chrome", title: "Sync"))
        XCTAssertEqual(loop.snapshot.phase, .recording)
    }
}
