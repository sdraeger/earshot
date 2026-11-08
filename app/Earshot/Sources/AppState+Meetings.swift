import Foundation

/// What the meeting card and the Meetings window read from the app.
extension AppState {
    /// The detected meeting waiting for the user's yes, nil when none is.
    var pendingConsentMeeting: DetectedMeeting? {
        watching.watchLoop?.pendingConsentMeeting
    }

    var isRecording: Bool {
        watching.isRecording
    }

    /// Finished jobs so far, so the Meetings window rereads the notes folder
    /// when one lands.
    var completedJobCount: Int {
        pipeline.queue.completedJobs.count
    }

    /// The meeting card's heading and title, nil when it has nothing to ask.
    /// A detected meeting comes before an in-person calendar one.
    var meetingCardContent: (heading: String, title: String)? {
        if let meeting = pendingConsentMeeting {
            return ("Meeting detected in \(meeting.pattern.appName)", meetings.cardTitle(for: meeting))
        }
        if let event = meetings.calendarCard {
            return ("Starting now in your calendar", event.title)
        }
        return nil
    }

    /// Start or Not now on the meeting card.
    func answerMeetingCard(start: Bool) {
        if pendingConsentMeeting != nil {
            answerPendingConsent(granted: start)
        } else {
            meetings.answerCalendarCard(start: start)
        }
    }
}
