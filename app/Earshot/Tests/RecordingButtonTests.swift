import AppKit
@testable import Earshot
import XCTest

@MainActor
final class RecordingButtonTests: XCTestCase {
    func testSilenceKeepsEveryBarAtTheFloor() {
        for height in VoiceBars.heights(levelDBFS: -120, phase: 1.7) {
            XCTAssertEqual(height, VoiceBars.floor, accuracy: 1e-9)
        }
    }

    func testLouderSpeechRaisesTheBars() {
        let quiet = VoiceBars.heights(levelDBFS: -45, phase: 0)
        let loud = VoiceBars.heights(levelDBFS: -15, phase: 0)
        for (q, l) in zip(quiet, loud) {
            XCTAssertGreaterThan(l, q)
            XCTAssertLessThanOrEqual(l, 1)
        }
    }

    private let visible = NSRect(x: 100, y: 50, width: 1000, height: 800)

    func testFrameSitsOnItsEdgeAndClampsTheFraction() {
        let inset = RecordingButtonPanel.edgeInset
        let high = RecordingButtonPanel.frame(edge: .right, fraction: 2, in: visible)
        let low = RecordingButtonPanel.frame(edge: .left, fraction: -1, in: visible)
        let top = RecordingButtonPanel.frame(edge: .top, fraction: 0.5, in: visible)
        let bottom = RecordingButtonPanel.frame(edge: .bottom, fraction: 0, in: visible)

        XCTAssertEqual(high.maxX, visible.maxX - inset)
        XCTAssertEqual(high.maxY, visible.maxY)
        XCTAssertEqual(low.minX, visible.minX + inset)
        XCTAssertEqual(low.minY, visible.minY)
        XCTAssertEqual(top.maxY, visible.maxY - inset)
        XCTAssertEqual(top.midX, visible.midX, accuracy: 0.001)
        XCTAssertGreaterThan(top.width, top.height, "lies down on the top edge")
        XCTAssertEqual(bottom.minY, visible.minY + inset)
        XCTAssertEqual(bottom.minX, visible.minX)
    }

    func testReleaseSnapsToTheNearestEdgeWhereItWasDropped() {
        let nearTop = RecordingButtonPanel.snap(center: NSPoint(x: 400, y: 830), in: visible)
        let nearLeft = RecordingButtonPanel.snap(center: NSPoint(x: 120, y: 450), in: visible)

        XCTAssertEqual(nearTop.edge, .top)
        XCTAssertEqual(nearLeft.edge, .left)
        let dropped = RecordingButtonPanel.frame(edge: nearTop.edge, fraction: nearTop.fraction, in: visible)
        XCTAssertEqual(dropped.midX, 400, accuracy: 0.001, "keeps its place along the edge")
    }

    func testAnOldSavedPositionStillMeansTheRightEdge() {
        let snapped = RecordingButtonPanel.snap(
            center: NSPoint(x: visible.maxX - 10, y: visible.midY), in: visible,
        )
        XCTAssertEqual(snapped.edge, .right)
        XCTAssertEqual(snapped.fraction, 0.5, accuracy: 0.001)
    }

    func testSettingDefaultsOnAndPersists() throws {
        let suite = "recording-button-\(getpid())-\(UUID().uuidString)"
        addTeardownBlock { DefaultsSuite.remove(suite) }
        let defaults = try XCTUnwrap(DefaultsSuite.open(suite))
        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.recordingButtonEnabled)
        settings.recordingButtonEnabled = false
        XCTAssertFalse(AppSettings(defaults: defaults).recordingButtonEnabled)
    }
}
