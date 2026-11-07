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

    func testOriginSitsAtTheRightEdgeAndClampsTheFraction() {
        let visible = NSRect(x: 100, y: 50, width: 1000, height: 800)
        let size = RecordingButtonPanel.panelSize
        let top = RecordingButtonPanel.origin(fraction: 2, in: visible)
        let bottom = RecordingButtonPanel.origin(fraction: -1, in: visible)
        XCTAssertEqual(top.x, visible.maxX - size.width - RecordingButtonPanel.edgeInset)
        XCTAssertEqual(top.y, visible.maxY - size.height)
        XCTAssertEqual(bottom.y, visible.minY)
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
