@testable import Earshot
import XCTest

@MainActor
final class MeetingLibraryTests: XCTestCase {
    private func makeFolder() throws -> URL {
        try makeTempDirectory(prefix: "meeting-library")
    }

    func testPairsNotesWithTranscriptNewestFirst() throws {
        let folder = try makeFolder()
        try "# Sprint review\n\nNotes".write(to: folder.appendingPathComponent("20260310_0900_sprint_review_abcd1234.md"), atomically: true, encoding: .utf8)
        try "[00:00] Alice: Hi".write(to: folder.appendingPathComponent("20260310_0900_sprint_review_abcd1234.txt"), atomically: true, encoding: .utf8)
        try "[00:00] Bob: Hey".write(to: folder.appendingPathComponent("20260312_1430_daily_standup_00ff11aa.txt"), atomically: true, encoding: .utf8)
        let library = MeetingLibrary { folder }

        library.reload()

        XCTAssertEqual(library.meetings.map(\.title), ["Daily standup", "Sprint review"])
        XCTAssertNil(library.meetings[0].notesURL, "a transcript-only meeting has no notes")
        XCTAssertNotNil(library.meetings[1].transcriptURL)
    }

    func testSearchReadsTitleAndText() throws {
        let folder = try makeFolder()
        try "[00:00] Bob: the budget".write(to: folder.appendingPathComponent("20260312_1430_daily_standup_00ff11aa.txt"), atomically: true, encoding: .utf8)
        let library = MeetingLibrary { folder }
        library.reload()
        let meeting = try XCTUnwrap(library.meetings.first)

        XCTAssertTrue(library.matches(meeting, query: "BUDGET"))
        XCTAssertTrue(library.matches(meeting, query: "standup"))
        XCTAssertFalse(library.matches(meeting, query: "roadmap"))
    }

    func testRenameRewritesOnlyTheTitleHeading() {
        XCTAssertEqual(MeetingLibrary.retitled("# Old\n\n## Old details", to: "New"), "# New\n\n## Old details")
        XCTAssertEqual(MeetingLibrary.retitled("No heading", to: "New"), "# New\n\nNo heading")
    }

    func testTitleAndDateFromTheFileName() throws {
        XCTAssertEqual(MeetingLibrary.title(fromFileName: "20260310_0900_sprint_review_abcd1234"), "Sprint review")
        let date = try XCTUnwrap(MeetingLibrary.date(fromFileName: "20260310_0900_sprint_review_abcd1234"))
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        XCTAssertEqual([parts.year, parts.month, parts.day, parts.hour, parts.minute], [2026, 3, 10, 9, 0])
    }

    func testTypedNotesBelongToTheirMeetingAndGoToTheTrashWithIt() throws {
        let folder = try makeFolder()
        let stem = "20260312_1430_daily_standup_00ff11aa"
        try "[00:00] Bob: Hey".write(to: folder.appendingPathComponent("\(stem).txt"), atomically: true, encoding: .utf8)
        try ProtocolGenerator.saveUserNotes("ship friday", basename: stem, dir: folder)
        let library = MeetingLibrary { folder }
        library.reload()
        let meeting = try XCTUnwrap(library.meetings.first)

        XCTAssertEqual(library.meetings.count, 1, "typed notes are no meeting of their own")
        XCTAssertEqual(library.userNotes(of: meeting), "ship friday")

        try library.delete(meeting)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("\(stem).usernotes").path))
    }
}
