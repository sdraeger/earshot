@testable import Earshot
import XCTest

/// Drives `WatchLoop.monitorManualRecording` end-to-end through the
/// manual-recording entry points with injected `pidAliveCheck` + `TestClock`,
/// so both stop conditions (pid exit, max-duration exceeded) run in the live
/// async loop without spawning a real subprocess.
@MainActor
final class WatchLoopMonitorTests: XCTestCase {
    /// When the monitored process dies, the next poll stops the recording. End state:
    /// `.idle`, no manual-recording info, recorder.stop called.
    func testMonitorStopsWhenPidDies() async throws {
        let clock = TestClock()
        let recorder = MockRecorder()
        recorder.mixPath = URL(fileURLWithPath: "/tmp/test_mix.wav")
        let loop = WatchLoop(
            recorderFactory: { recorder },
            pollInterval: 0.05,
            nowProvider: { clock.now },
            sleepProvider: { await clock.sleep(for: $0) },
            pidAliveCheck: { _ in false }, // simulated process already exited
        )
        loop.permissionChecker = {
            HealthCheckResult(screenRecording: .healthy, microphone: .healthy)
        }

        try await loop.startManualRecording(pid: 42, appName: "Test", title: "T")

        await waitFor(loop.snapshot.phase == .idle, timeout: .seconds(1))
        XCTAssertEqual(loop.snapshot.phase, .idle)
        XCTAssertNil(loop.snapshot.manualRecordingInfo)
        XCTAssertTrue(recorder.stopCalled, "Recorder.stop must be called when pid dies")
    }

    /// When the process stays alive past `maxDuration` virtual time, the
    /// next poll runs the same stop path.
    func testMonitorStopsOnMaxDurationExceeded() async throws {
        let clock = TestClock()
        let recorder = MockRecorder()
        recorder.mixPath = URL(fileURLWithPath: "/tmp/test_mix.wav")
        let loop = WatchLoop(
            recorderFactory: { recorder },
            pollInterval: 0.05,
            maxDuration: 0.05,
            nowProvider: { clock.now },
            sleepProvider: { await clock.sleep(for: $0) },
            pidAliveCheck: { _ in true }, // process never dies
        )
        loop.permissionChecker = {
            HealthCheckResult(screenRecording: .healthy, microphone: .healthy)
        }

        try await loop.startManualRecording(pid: 42, appName: "Test", title: "T")

        await waitFor(loop.snapshot.phase == .idle, timeout: .seconds(1))
        XCTAssertEqual(loop.snapshot.phase, .idle)
        XCTAssertNil(loop.snapshot.manualRecordingInfo)
        XCTAssertTrue(recorder.stopCalled, "Recorder.stop must be called when maxDuration hits")
    }

    /// A microphone-only recording has no process to watch: the liveness
    /// check is never consulted, and the duration cap still ends it.
    func testMicrophoneRecordingStopsOnlyAtMaxDuration() async throws {
        let clock = TestClock()
        let recorder = MockRecorder()
        recorder.mixPath = URL(fileURLWithPath: "/tmp/test_mix.wav")
        var livenessChecks = 0
        let loop = WatchLoop(
            recorderFactory: { recorder },
            pollInterval: 0.05,
            maxDuration: 0.05,
            nowProvider: { clock.now },
            sleepProvider: { await clock.sleep(for: $0) },
            pidAliveCheck: { _ in
                livenessChecks += 1
                return false
            },
        )
        loop.permissionChecker = {
            HealthCheckResult(screenRecording: .healthy, microphone: .healthy)
        }

        try await loop.startMicrophoneRecording()

        await waitFor(loop.snapshot.phase == .idle, timeout: .seconds(1))
        XCTAssertTrue(recorder.stopCalled)
        XCTAssertEqual(livenessChecks, 0)
    }
}
