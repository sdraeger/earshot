@testable import Earshot
import XCTest

final class CalendarMeetingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(_ id: String, startsIn minutes: Double, length: Double = 30, attendees: [String] = ["Ann"], online: Bool = false) -> CalendarMeeting {
        CalendarMeeting(
            id: id, title: id, start: now.addingTimeInterval(minutes * 60),
            end: now.addingTimeInterval((minutes + length) * 60), attendees: attendees, isOnline: online,
        )
    }

    func testCurrentPicksTheEventThatStartedClosest() {
        let events = [event("all-hands", startsIn: -50, length: 120), event("sync", startsIn: -2), event("later", startsIn: 30)]

        XCTAssertEqual(CalendarMeeting.current(in: events, at: now)?.id, "sync")
    }

    func testCurrentCountsAnEventAboutToStart() {
        XCTAssertEqual(CalendarMeeting.current(in: [event("soon", startsIn: 3)], at: now)?.id, "soon")
        XCTAssertNil(CalendarMeeting.current(in: [event("later", startsIn: 10)], at: now))
    }

    func testOnlyAFreshInPersonMeetingWithOthersIsAnnounced() {
        let events = [
            event("online", startsIn: -1, online: true),
            event("alone", startsIn: -1, attendees: []),
            event("old", startsIn: -5),
            event("seen", startsIn: -1),
            event("room", startsIn: -1),
        ]

        XCTAssertEqual(CalendarMeeting.startingInPerson(in: events, at: now, except: ["seen"])?.id, "room")
    }

    func testMeetingLinksMarkAnEventOnline() {
        XCTAssertTrue(CalendarMeeting.isOnline([nil, "Join: https://us02web.zoom.us/j/123"]))
        XCTAssertFalse(CalendarMeeting.isOnline(["Room 4B", nil]))
    }
}
