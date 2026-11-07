@testable import Earshot
import XCTest

@MainActor
final class MenuBarIconTests: XCTestCase {
    func testImageWithNoBadgeIsTemplate() {
        let image = MenuBarIcon.image(badge: .inactive)
        XCTAssertTrue(image.isTemplate)
    }

    func testImageSizeIs18x18() {
        let image = MenuBarIcon.image(badge: .inactive)
        XCTAssertEqual(image.size.width, 18, accuracy: 0.01)
        XCTAssertEqual(image.size.height, 18, accuracy: 0.01)
    }

    func testRecordOnlyOverlayProducesNonTemplateImageOverAnyBadge() {
        for badge in BadgeKind.allCases {
            let image = MenuBarIcon.image(badge: badge, recordOnlyOverlay: true)
            XCTAssertFalse(
                image.isTemplate,
                "record-only overlay must be non-template for \(badge) so the red dot stays red",
            )
        }
    }

    func testRecordOnlyOverlayDefaultsOffStaysTemplate() {
        let image = MenuBarIcon.image(badge: .inactive)
        XCTAssertTrue(image.isTemplate, "without overlay flag, default rendering stays template")
    }

    /// Regression test: when a non-animated badge (e.g. `.inactive`) is rendered with the
    /// record-only overlay, it must NOT pick up the live `animationFrame` — otherwise the
    /// idle waveform bounces as if recording. See MenuBarIcon.image(...) frame-clamp logic.
    func testRecordOnlyOverlayDoesNotAnimateStaticBadges() {
        let staticBadges: [BadgeKind] = [.inactive, .userAction, .done, .error, .updateAvailable]
        for badge in staticBadges {
            let frame0 = MenuBarIcon.image(badge: badge, animationFrame: 0, recordOnlyOverlay: true)
            let frame3 = MenuBarIcon.image(badge: badge, animationFrame: 3, recordOnlyOverlay: true)
            XCTAssertEqual(
                frame0.tiffRepresentation,
                frame3.tiffRepresentation,
                "Static badge \(badge) should render identically across frames under recordOnlyOverlay",
            )
        }
    }

    /// Inverse check: animated badges (e.g. `.recording`) MUST advance their frame under the
    /// overlay — otherwise the live waveform bounce is killed when record-only is enabled.
    func testRecordOnlyOverlayKeepsAnimatedBadgesAnimating() {
        let animatedBadges: [BadgeKind] = [.recording, .transcribing, .diarizing, .processing]
        for badge in animatedBadges {
            let frame0 = MenuBarIcon.image(badge: badge, animationFrame: 0, recordOnlyOverlay: true)
            let frame3 = MenuBarIcon.image(badge: badge, animationFrame: 3, recordOnlyOverlay: true)
            XCTAssertNotEqual(
                frame0.tiffRepresentation,
                frame3.tiffRepresentation,
                "Animated badge \(badge) should advance under recordOnlyOverlay",
            )
        }
    }

    // MARK: - Per-channel silence overlay

    func testMicSilentOverlayProducesNonTemplateImage() {
        for badge in BadgeKind.allCases {
            let image = MenuBarIcon.image(badge: badge, micSilentOverlay: true)
            XCTAssertFalse(image.isTemplate, "mic-silent overlay must be non-template for \(badge)")
        }
    }

    func testAppSilentOverlayProducesNonTemplateImage() {
        for badge in BadgeKind.allCases {
            let image = MenuBarIcon.image(badge: badge, appSilentOverlay: true)
            XCTAssertFalse(image.isTemplate, "app-silent overlay must be non-template for \(badge)")
        }
    }

    func testChannelOverlaysDefaultOff() {
        let image = MenuBarIcon.image(badge: .transcribing)
        XCTAssertTrue(image.isTemplate, "without overlay flag, transcribing stays template")
    }

    func testMicAndAppSilentRenderDistinctImages() {
        let micRed = MenuBarIcon.image(badge: .recording, animationFrame: 0, micSilentOverlay: true)
        let appRed = MenuBarIcon.image(badge: .recording, animationFrame: 0, appSilentOverlay: true)
        let bothRed = MenuBarIcon.image(badge: .recording, animationFrame: 0, micSilentOverlay: true, appSilentOverlay: true)
        let normal = MenuBarIcon.image(badge: .recording, animationFrame: 0)
        XCTAssertNotEqual(micRed.tiffRepresentation, normal.tiffRepresentation)
        XCTAssertNotEqual(appRed.tiffRepresentation, normal.tiffRepresentation)
        XCTAssertNotEqual(micRed.tiffRepresentation, appRed.tiffRepresentation, "top-half and bottom-half tint must differ")
        XCTAssertNotEqual(bothRed.tiffRepresentation, micRed.tiffRepresentation)
        XCTAssertNotEqual(bothRed.tiffRepresentation, appRed.tiffRepresentation)
    }

    func testAllBadgeKindsProduceValidImages() {
        // Badges that paint a colored mark (red dot / exclamation) must stay non-template
        // so the color survives macOS's monochrome template tinting.
        let nonTemplateBadges: Set<BadgeKind> = [.error, .recording]
        for badge in BadgeKind.allCases {
            let image = MenuBarIcon.image(badge: badge)
            if nonTemplateBadges.contains(badge) {
                XCTAssertFalse(image.isTemplate, "Badge \(badge) should be non-template (colored)")
            } else {
                XCTAssertTrue(image.isTemplate, "Badge \(badge) should produce a template image")
            }
            XCTAssertEqual(image.size.width, 18, accuracy: 0.01, "Badge \(badge) width")
            XCTAssertEqual(image.size.height, 18, accuracy: 0.01, "Badge \(badge) height")
        }
    }

    func testAnimatedBadgeKinds() {
        XCTAssertTrue(BadgeKind.recording.isAnimated)
        XCTAssertTrue(BadgeKind.transcribing.isAnimated)
        XCTAssertTrue(BadgeKind.diarizing.isAnimated)
        XCTAssertTrue(BadgeKind.processing.isAnimated)
        XCTAssertFalse(BadgeKind.inactive.isAnimated)
        XCTAssertFalse(BadgeKind.done.isAnimated)
    }

    func testAllAnimationFramesProduceValidImages() {
        let animatedBadges: [BadgeKind] = [.recording, .transcribing, .diarizing, .processing]
        for badge in animatedBadges {
            for frame in 0 ..< MenuBarIcon.frameCount {
                let image = MenuBarIcon.image(badge: badge, animationFrame: frame)
                // Recording's dot is red, so it cannot be a template.
                XCTAssertEqual(image.isTemplate, badge != .recording, "\(badge) frame \(frame)")
                XCTAssertEqual(image.size.width, 18, accuracy: 0.01)
                XCTAssertEqual(image.size.height, 18, accuracy: 0.01)
            }
        }
    }

    // MARK: - Frame Wrapping

    func testAnimationFrameWrapsAroundFrameCount() {
        let badge = BadgeKind.transcribing
        let normal = MenuBarIcon.image(badge: badge, animationFrame: 2)
        let wrapped = MenuBarIcon.image(badge: badge, animationFrame: 2 + MenuBarIcon.frameCount)
        XCTAssertTrue(normal.isTemplate)
        XCTAssertTrue(wrapped.isTemplate)
        XCTAssertEqual(normal.size, wrapped.size)
    }

    // MARK: - Permission Overlay

    func testPermissionOverlayIsNonTemplate() {
        // Transcribing is normally a template image — with the overlay it must become non-template
        // because the red exclamation dot can't be monochrome.
        let image = MenuBarIcon.image(badge: .transcribing, animationFrame: 0, permissionOverlay: true)
        XCTAssertFalse(image.isTemplate)
    }

    func testPermissionOverlayAppliesToAllActiveBadges() {
        for badge in BadgeKind.allCases {
            let image = MenuBarIcon.image(badge: badge, animationFrame: 0, permissionOverlay: true)
            XCTAssertFalse(image.isTemplate, "Overlay on \(badge) should be non-template")
            XCTAssertEqual(image.size.width, 18, accuracy: 0.01)
            XCTAssertEqual(image.size.height, 18, accuracy: 0.01)
        }
    }

    func testPermissionOverlayDefaultsToFalse() {
        let withoutParam = MenuBarIcon.image(badge: .recording, animationFrame: 0)
        let explicitFalse = MenuBarIcon.image(badge: .recording, animationFrame: 0, permissionOverlay: false)
        XCTAssertEqual(withoutParam.isTemplate, explicitFalse.isTemplate)
    }

    func testLargeAnimationFrameDoesNotCrash() {
        for badge in BadgeKind.allCases where badge.isAnimated {
            let image = MenuBarIcon.image(badge: badge, animationFrame: 999)
            XCTAssertEqual(image.size.width, 18, accuracy: 0.01, "Large frame index should wrap safely for \(badge)")
        }
    }

    // MARK: - BadgeKind.compute()

    // 1. Recording while watchLoop recording
    func testCompute_watchLoopRecording_returnsRecording() {
        let result = BadgeKind.compute(
            watchLoopActive: true,
            watchLoopState: .recording,
            transcriberState: .idle,
            activeJobState: nil,
            updateAvailable: false,
        )
        XCTAssertEqual(result, .recording)
    }

    // 2. Recording takes priority over transcriberState
    func testCompute_watchLoopRecording_priorityOverTranscriberState() {
        let result = BadgeKind.compute(
            watchLoopActive: true,
            watchLoopState: .recording,
            transcriberState: .watching,
            activeJobState: nil,
            updateAvailable: false,
        )
        XCTAssertEqual(result, .recording)
    }

    // 6. Error for transcriberError
    func testCompute_transcriberError_returnsError() {
        let result = BadgeKind.compute(
            watchLoopActive: true,
            watchLoopState: .watching,
            transcriberState: .error,
            activeJobState: nil,
            updateAvailable: false,
        )
        XCTAssertEqual(result, .error)
    }

    // 10. ActiveJob transcribing (watchLoop inactive)
    func testCompute_activeJobTranscribing_returnsTranscribing() {
        let result = BadgeKind.compute(
            watchLoopActive: false,
            watchLoopState: .idle,
            transcriberState: .idle,
            activeJobState: .transcribing,
            updateAvailable: false,
        )
        XCTAssertEqual(result, .transcribing)
    }

    // 11. ActiveJob diarizing
    func testCompute_activeJobDiarizing_returnsDiarizing() {
        let result = BadgeKind.compute(
            watchLoopActive: false,
            watchLoopState: .idle,
            transcriberState: .idle,
            activeJobState: .diarizing,
            updateAvailable: false,
        )
        XCTAssertEqual(result, .diarizing)
    }

    // 12. ActiveJob generatingProtocol → processing
    func testCompute_activeJobGeneratingProtocol_returnsProcessing() {
        let result = BadgeKind.compute(
            watchLoopActive: false,
            watchLoopState: .idle,
            transcriberState: .idle,
            activeJobState: .generatingProtocol,
            updateAvailable: false,
        )
        XCTAssertEqual(result, .processing)
    }

    // 13. ActiveJob waiting → processing
    func testCompute_activeJobWaiting_returnsProcessing() {
        let result = BadgeKind.compute(
            watchLoopActive: false,
            watchLoopState: .idle,
            transcriberState: .idle,
            activeJobState: .waiting,
            updateAvailable: false,
        )
        XCTAssertEqual(result, .processing)
    }

    // 14. ActiveJob done → processing
    func testCompute_activeJobDone_returnsProcessing() {
        let result = BadgeKind.compute(
            watchLoopActive: false,
            watchLoopState: .idle,
            transcriberState: .idle,
            activeJobState: .done,
            updateAvailable: false,
        )
        XCTAssertEqual(result, .processing)
    }

    // 15. ActiveJob error → processing
    func testCompute_activeJobError_returnsProcessing() {
        let result = BadgeKind.compute(
            watchLoopActive: false,
            watchLoopState: .idle,
            transcriberState: .idle,
            activeJobState: .error,
            updateAvailable: false,
        )
        XCTAssertEqual(result, .processing)
    }

    // 16. UpdateAvailable when all idle
    func testCompute_updateAvailable_returnsUpdateAvailable() {
        let result = BadgeKind.compute(
            watchLoopActive: false,
            watchLoopState: .idle,
            transcriberState: .idle,
            activeJobState: nil,
            updateAvailable: true,
        )
        XCTAssertEqual(result, .updateAvailable)
    }

    // 17. Inactive when all idle
    func testCompute_allIdle_returnsInactive() {
        let result = BadgeKind.compute(
            watchLoopActive: false,
            watchLoopState: .idle,
            transcriberState: .idle,
            activeJobState: nil,
            updateAvailable: false,
        )
        XCTAssertEqual(result, .inactive)
    }

    // 18. WatchLoop active but idle transcriberState → inactive
    func testCompute_watchLoopActiveIdleTranscriber_returnsInactive() {
        let result = BadgeKind.compute(
            watchLoopActive: true,
            watchLoopState: .watching,
            transcriberState: .idle,
            activeJobState: nil,
            updateAvailable: false,
        )
        XCTAssertEqual(result, .inactive)
    }

    // 19. ActiveJob takes priority over updateAvailable
    func testCompute_activeJob_priorityOverUpdateAvailable() {
        let result = BadgeKind.compute(
            watchLoopActive: false,
            watchLoopState: .idle,
            transcriberState: .idle,
            activeJobState: .transcribing,
            updateAvailable: true,
        )
        XCTAssertEqual(result, .transcribing)
    }

    // 20. WatchLoop recording takes priority over activeJob and updateAvailable
    func testCompute_watchLoopRecording_priorityOverActiveJobAndUpdate() {
        let result = BadgeKind.compute(
            watchLoopActive: true,
            watchLoopState: .recording,
            transcriberState: .idle,
            activeJobState: .transcribing,
            updateAvailable: true,
        )
        XCTAssertEqual(result, .recording)
    }

    // 21. WatchLoop active with .watching transcriberState → falls through to inactive
    func testCompute_watchLoopActiveWatchingState_fallsThroughToInactive() {
        let result = BadgeKind.compute(
            watchLoopActive: true,
            watchLoopState: .watching,
            transcriberState: .watching,
            activeJobState: nil,
            updateAvailable: false,
        )
        XCTAssertEqual(result, .inactive)
    }

    func testCompute_permissionBroken_returnsError() {
        let result = BadgeKind.compute(
            watchLoopActive: false,
            watchLoopState: .idle,
            transcriberState: .idle,
            activeJobState: nil,
            updateAvailable: false,
            permissionProblem: true,
        )
        XCTAssertEqual(result, .error)
    }

    func testCompute_recordingOverridesPermissionProblem() {
        let result = BadgeKind.compute(
            watchLoopActive: true,
            watchLoopState: .recording,
            transcriberState: .idle,
            activeJobState: nil,
            updateAvailable: false,
            permissionProblem: true,
        )
        XCTAssertEqual(result, .recording)
    }

    func testCompute_permissionProblemOverridesUpdate() {
        let result = BadgeKind.compute(
            watchLoopActive: false,
            watchLoopState: .idle,
            transcriberState: .idle,
            activeJobState: nil,
            updateAvailable: true,
            permissionProblem: true,
        )
        XCTAssertEqual(result, .error)
    }
}
