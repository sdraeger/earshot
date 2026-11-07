@testable import Earshot
import XCTest

final class DetectionConfirmationTests: XCTestCase {
    func testConfirmsOnlyAfterConsecutiveRounds() {
        var confirmation = DetectionConfirmation(threshold: 2)
        XCTAssertEqual(confirmation.endRound(seen: ["Zoom"]), [])
        XCTAssertEqual(confirmation.endRound(seen: ["Zoom"]), ["Zoom"])
    }

    func testARoundWithoutTheKeyStartsItsCountOver() {
        var confirmation = DetectionConfirmation(threshold: 2)
        _ = confirmation.endRound(seen: ["Zoom"])
        _ = confirmation.endRound(seen: ["Teams"])
        XCTAssertEqual(confirmation.endRound(seen: ["Zoom"]), [])
    }

    func testResetCoolsDownOnlyTheNamedKey() {
        var confirmation = DetectionConfirmation(threshold: 1)
        let now = Date()
        confirmation.reset(coolingDown: "Zoom", now: now)
        XCTAssertTrue(confirmation.isCoolingDown("Zoom", now: now.addingTimeInterval(4)))
        XCTAssertFalse(confirmation.isCoolingDown("Zoom", now: now.addingTimeInterval(6)))
        XCTAssertFalse(confirmation.isCoolingDown("Teams", now: now))
    }
}
