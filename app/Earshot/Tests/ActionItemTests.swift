@testable import Earshot
import XCTest

final class ActionItemTests: XCTestCase {
    func testReadsTheBuiltInTasksTable() {
        let notes = """
        # Meeting Protocol - Launch
        ## Decisions
        - Ship on Friday

        ## Aufgaben
        | Aufgabe | Verantwortlich | Frist | Priorität |
        |------|-------------|----------|----------|
        | Write the release notes | Ann | 2026-11-20 | 🔴 high |
        | Book the room | offen | open | 🟢 low |

        ## Open Questions
        - Who pays?
        """

        let items = ActionItem.parse(notes)

        XCTAssertEqual(items.map(\.title), ["Write the release notes", "Book the room"])
        XCTAssertEqual(items.map(\.owner), ["Ann", nil])
        XCTAssertNotNil(items[0].due)
        XCTAssertNil(items[1].due)
    }

    func testReadsTemplateBullets() {
        let notes = """
        ## Action Items
        - Send the deck — Bo — 2026-12-01
        - [ ] Follow up with legal — open — open
        ## Notes
        - not a task
        """

        let items = ActionItem.parse(notes)

        XCTAssertEqual(items.map(\.title), ["Send the deck", "Follow up with legal"])
        XCTAssertEqual(items.map(\.owner), ["Bo", nil])
    }

    func testNotesWithoutATasksHeadingHaveNone() {
        XCTAssertEqual(ActionItem.parse("# Title\n- just a bullet"), [])
    }
}
