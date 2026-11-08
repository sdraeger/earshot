@testable import Earshot
import XCTest

@MainActor
final class MeetingContextTests: XCTestCase {
    func testAnEndingRecordingTakesTheCalendarTitleAttendeesAndNotes() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("meeting-context-\(UUID())")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: tmpDir) }
        let queue = PipelineQueue(logDir: tmpDir)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var askedAt: Date?
        // A named local: as a trailing closure it would bind to the init's last parameter.
        let meetingContext: (Date) -> MeetingContext = { date in
            askedAt = date
            return MeetingContext(title: "Budget review", attendees: ["Ann", "Bo"], userNotes: "cut travel")
        }
        let loop = WatchLoop(pipelineQueue: queue, meetingContext: meetingContext)

        loop.enqueueRecording(
            title: "Zoom Meeting", appName: "zoom.us",
            recording: RecordingResult(
                mixPath: URL(fileURLWithPath: "/tmp/ctx_mix.wav"), appPath: nil, micPath: nil,
                micDelay: 0, recordingStartDate: start,
            ),
            trigger: .auto, participants: ["Bo", "Cy"],
        )

        let job = try XCTUnwrap(queue.jobs.first)
        XCTAssertEqual(askedAt, start)
        XCTAssertEqual(job.meetingTitle, "Budget review")
        XCTAssertEqual(job.participants, ["Bo", "Cy", "Ann"])
        XCTAssertEqual(job.userNotes, "cut travel")
    }

    func testAPersonSpeaksWhenATranscriptLineIsTheirs() {
        let transcript = "[00:01] Ann: hello\n[00:04] Bo Li: hi Ann"

        XCTAssertTrue(MeetingsController.speaks("Bo Li", in: transcript))
        XCTAssertTrue(MeetingsController.speaks("Ann", in: transcript))
        XCTAssertFalse(MeetingsController.speaks("Bo", in: transcript))
    }
}
