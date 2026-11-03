@testable import MeetingTranscriber
import XCTest

final class BadgeKindComputeTests: XCTestCase {
    // MARK: WatchLoop active

    func testBadgeRecordingWhenWatchLoopStateIsRecording() {
        let badge = BadgeKind.compute(
            watchLoopActive: true,
            watchLoopState: .recording,
            transcriberState: .recording,
            activeJobState: nil,
            updateAvailable: false,
        )
        XCTAssertEqual(badge, .recording)
    }

    /// An open browser-consent prompt shows on the icon, not only as a
    /// notification that may never be seen (issue #814).
    func testBadgeUserActionWhileConsentIsPending() {
        let badge = BadgeKind.compute(
            watchLoopActive: true,
            watchLoopState: .watching,
            transcriberState: .watching,
            activeJobState: .transcribing,
            updateAvailable: true,
            consentPending: true,
        )
        XCTAssertEqual(badge, .userAction)
    }

    func testAnErrorOutranksAPendingConsent() {
        let badge = BadgeKind.compute(
            watchLoopActive: true,
            watchLoopState: .watching,
            transcriberState: .error,
            activeJobState: nil,
            updateAvailable: false,
            consentPending: true,
        )
        XCTAssertEqual(badge, .error)
    }

    func testRecordingOutranksAPendingConsent() {
        // A native call recording while a browser prompt waits: the running
        // recording is the state the icon must show.
        let badge = BadgeKind.compute(
            watchLoopActive: true,
            watchLoopState: .recording,
            transcriberState: .recording,
            activeJobState: nil,
            updateAvailable: false,
            consentPending: true,
        )
        XCTAssertEqual(badge, .recording)
    }

    func testBadgeErrorForErrorState() {
        let badge = BadgeKind.compute(
            watchLoopActive: true,
            watchLoopState: .watching,
            transcriberState: .error,
            activeJobState: nil,
            updateAvailable: false,
        )
        XCTAssertEqual(badge, .error)
    }

    // MARK: WatchLoop inactive, active job

    func testBadgeTranscribingForActiveTranscribingJob() {
        let badge = BadgeKind.compute(
            watchLoopActive: false,
            watchLoopState: .idle,
            transcriberState: .idle,
            activeJobState: .transcribing,
            updateAvailable: false,
        )
        XCTAssertEqual(badge, .transcribing)
    }

    func testBadgeDiarizingForActiveDiarizingJob() {
        let badge = BadgeKind.compute(
            watchLoopActive: false,
            watchLoopState: .idle,
            transcriberState: .idle,
            activeJobState: .diarizing,
            updateAvailable: false,
        )
        XCTAssertEqual(badge, .diarizing)
    }

    func testBadgeProcessingForActiveGeneratingProtocolJob() {
        let badge = BadgeKind.compute(
            watchLoopActive: false,
            watchLoopState: .idle,
            transcriberState: .idle,
            activeJobState: .generatingProtocol,
            updateAvailable: false,
        )
        XCTAssertEqual(badge, .processing)
    }

    func testWatchLoopTakesPriorityOverActiveJob() {
        let badge = BadgeKind.compute(
            watchLoopActive: true,
            watchLoopState: .recording,
            transcriberState: .recording,
            activeJobState: .transcribing,
            updateAvailable: false,
        )
        XCTAssertEqual(badge, .recording)
    }

    // MARK: No watchloop, no jobs

    func testBadgeUpdateAvailableWhenNoWatchLoopNoJobs() {
        let badge = BadgeKind.compute(
            watchLoopActive: false,
            watchLoopState: .idle,
            transcriberState: .idle,
            activeJobState: nil,
            updateAvailable: true,
        )
        XCTAssertEqual(badge, .updateAvailable)
    }

    func testBadgeInactiveWhenNothingActive() {
        let badge = BadgeKind.compute(
            watchLoopActive: false,
            watchLoopState: .idle,
            transcriberState: .idle,
            activeJobState: nil,
            updateAvailable: false,
        )
        XCTAssertEqual(badge, .inactive)
    }
}
