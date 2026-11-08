import EventKit
import Foundation

/// A calendar event as Earshot uses it: what to call the meeting, who was
/// invited, and whether it happens in a meeting app (which the detector
/// finds) or in the room (which only the calendar announces).
struct CalendarMeeting: Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let attendees: [String]
    let isOnline: Bool

    /// The event a recording that starts at `date` belongs to: one running
    /// then (or starting within `lead`), the one that started closest to
    /// `date` when several overlap.
    static func current(in events: [Self], at date: Date, lead: TimeInterval = 5 * 60) -> Self? {
        events.filter { $0.start.addingTimeInterval(-lead) <= date && date < $0.end }
            .min { abs($0.start.timeIntervalSince(date)) < abs($1.start.timeIntervalSince(date)) }
    }

    /// Hosts of the meeting apps a link in the event can point at.
    static let onlineHosts = [
        "zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com",
        "whereby.com", "facetime.apple.com", "meet.jit.si", "slack.com/huddle",
    ]

    static func isOnline(_ texts: [String?]) -> Bool {
        let text = texts.compactMap(\.self).joined(separator: " ").lowercased()
        return onlineHosts.contains { text.contains($0) }
    }
}

/// One task from a meeting's notes.
struct ActionItem: Equatable {
    let title: String
    let owner: String?
    let due: Date?

    /// The tasks under a heading that names them (Tasks, Action Items, To-dos,
    /// Next Steps, or the German words), read from table rows (task, owner,
    /// deadline) or bullets (`task — owner — due`). Placeholders such as
    /// "open" become nil.
    static func parse(_ markdown: String) -> [Self] {
        var items: [Self] = []
        var inSection = false
        for raw in markdown.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") {
                let heading = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces).lowercased()
                inSection = sectionWords.contains { heading.hasPrefix($0) }
                continue
            }
            guard inSection else { continue }
            if line.hasPrefix("|") {
                let cells = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                guard let first = cells.first, !first.allSatisfy({ "-: ".contains($0) }),
                      !headerWords.contains(first.lowercased()) else { continue }
                items.append(make(cells))
            } else if let bullet = ["- [ ] ", "- [x] ", "- ", "* "].first(where: line.hasPrefix) {
                let cells = line.dropFirst(bullet.count)
                    .components(separatedBy: " — ").flatMap { $0.components(separatedBy: " | ") }
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                items.append(make(cells))
            }
        }
        return items.filter { !$0.title.isEmpty && !isOpen($0.title) }
    }

    private static let sectionWords = [
        "tasks", "action items", "to-dos", "todos", "next steps", "aufgaben", "to-do", "nächste schritte",
    ]
    private static let headerWords: Set = ["task", "aufgabe", "action item", "todo", "to-do"]

    private static func make(_ cells: [String]) -> Self {
        let owner = cells.count > 1 && !isOpen(cells[1]) ? cells[1] : nil
        let due = cells.count > 2 ? dueFormatter.date(from: String(cells[2].prefix(10))) : nil
        return Self(title: cells[0].replacingOccurrences(of: "**", with: ""), owner: owner, due: due)
    }

    private static func isOpen(_ text: String) -> Bool {
        let text = text.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]() -—"))
        return text.isEmpty || ["open", "offen", "n/a", "tbd", "none", "-"].contains(text)
    }

    private static let dueFormatter = DateFormatter.filenameStamp("yyyy-MM-dd")
}

/// The user's calendars and reminders, through EventKit. Every read is empty
/// until the user grants access, which `requestCalendarAccess` asks for.
@MainActor
final class MeetingCalendar {
    private let store = EKEventStore()

    var hasCalendarAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    func requestCalendarAccess() async -> Bool {
        await (try? store.requestFullAccessToEvents()) ?? false
    }

    /// Timed events from an hour before `date` to an hour after.
    func meetings(around date: Date) -> [CalendarMeeting] {
        guard hasCalendarAccess else { return [] }
        let predicate = store.predicateForEvents(
            withStart: date.addingTimeInterval(-3600), end: date.addingTimeInterval(3600), calendars: nil,
        )
        return store.events(matching: predicate).filter { !$0.isAllDay }.map { event in
            CalendarMeeting(
                id: event.calendarItemIdentifier + "\(event.startDate.timeIntervalSince1970)",
                title: event.title ?? "",
                start: event.startDate,
                end: event.endDate,
                attendees: (event.attendees ?? []).filter { !$0.isCurrentUser }.compactMap(Self.name),
                isOnline: CalendarMeeting.isOnline([event.url?.absoluteString, event.location, event.notes]),
            )
        }
    }

    func meeting(at date: Date) -> CalendarMeeting? {
        CalendarMeeting.current(in: meetings(around: date), at: date)
    }

    /// Adds `items` to a Reminders list named Earshot, made on first use.
    /// Returns how many were added; throws when access is refused.
    func addReminders(_ items: [ActionItem], meetingTitle: String) async throws -> Int {
        guard try await store.requestFullAccessToReminders() else { throw ReminderError.accessDenied }
        let list = try remindersList()
        for item in items {
            let reminder = EKReminder(eventStore: store)
            reminder.calendar = list
            reminder.title = item.owner.map { "\(item.title) (\($0))" } ?? item.title
            reminder.notes = "From the meeting “\(meetingTitle)”"
            if let due = item.due {
                reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: due)
            }
            try store.save(reminder, commit: false)
        }
        try store.commit()
        return items.count
    }

    enum ReminderError: LocalizedError {
        case accessDenied
        var errorDescription: String? {
            "Earshot can't reach Reminders. Allow it in System Settings → Privacy & Security → Reminders."
        }
    }

    private func remindersList() throws -> EKCalendar {
        if let list = store.calendars(for: .reminder).first(where: { $0.title == "Earshot" }) { return list }
        let list = EKCalendar(for: .reminder, eventStore: store)
        list.title = "Earshot"
        guard let source = store.defaultCalendarForNewReminders()?.source else { throw ReminderError.accessDenied }
        list.source = source
        try store.saveCalendar(list, commit: true)
        return list
    }

    private static func name(_ participant: EKParticipant) -> String? {
        if let name = participant.name, !name.isEmpty, !name.contains("@") { return name }
        let email = participant.url.absoluteString.replacingOccurrences(of: "mailto:", with: "")
        return email.split(separator: "@").first.map(String.init)
    }
}
