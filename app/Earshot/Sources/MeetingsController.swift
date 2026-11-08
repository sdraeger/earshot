import Foundation
import Observation

/// Everything about meetings past the recording itself: the notepad typed
/// during one, the calendar that names it and announces in-person ones, and
/// what the Meetings window does with finished ones (regenerate with another
/// template, ask across all of them, send tasks to Reminders, list them by
/// person).
@Observable
@MainActor
final class MeetingsController {
    let library: MeetingLibrary
    @ObservationIgnored let calendar = MeetingCalendar()

    /// What the user types in the Meetings window while recording. Taken by
    /// the recording that ends next, and cleared then.
    var notepad = ""

    /// An in-person calendar meeting that just started, for the meeting card.
    private(set) var calendarCard: CalendarMeeting?
    @ObservationIgnored private var announced: Set<String> = []
    @ObservationIgnored private var calendarTask: Task<Void, Never>?

    private let settings: AppSettings
    private let pipeline: PipelineController
    private let watching: WatchingController

    init(settings: AppSettings, pipeline: PipelineController, watching: WatchingController) {
        self.settings = settings
        self.pipeline = pipeline
        self.watching = watching
        library = MeetingLibrary { [pipeline] in
            pipeline.outputDirectory.resolve().appendingPathComponent("protocols", isDirectory: true)
        }
    }

    // MARK: - Recording

    /// See `WatchLoop.meetingContext`.
    func context(at date: Date) -> MeetingContext {
        let event = settings.calendarEnabled ? calendar.meeting(at: date) : nil
        let notes = notepad.trimmingCharacters(in: .whitespacesAndNewlines)
        notepad = ""
        return MeetingContext(
            title: event.flatMap { $0.title.isEmpty ? nil : $0.title },
            attendees: event?.attendees ?? [],
            userNotes: notes.isEmpty ? nil : notes,
        )
    }

    /// The meeting card's title for a detected meeting: the calendar event on
    /// now, or the window title.
    func cardTitle(for meeting: DetectedMeeting) -> String {
        let event = settings.calendarEnabled ? calendar.meeting(at: Date()) : nil
        return event?.title ?? WatchLoop.cleanTitle(meeting.windowTitle)
    }

    /// Checks the calendar every 30 seconds for an in-person meeting starting.
    func startCalendarWatch() {
        guard calendarTask == nil else { return }
        calendarTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.checkCalendar()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private func checkCalendar(now: Date = Date()) {
        guard settings.calendarEnabled, calendarCard == nil, !watching.isRecording else { return }
        let starting = CalendarMeeting.startingInPerson(in: calendar.meetings(around: now), at: now, except: announced)
        guard let starting else { return }
        announced.insert(starting.id)
        calendarCard = starting
    }

    /// Start records the microphone; the recording takes the event's title
    /// from the calendar when it ends.
    func answerCalendarCard(start: Bool) {
        calendarCard = nil
        if start { watching.startMicrophoneRecording() }
    }

    // MARK: - Finished meetings

    /// Writes new notes for `meeting` from its transcript with `template`.
    func regenerate(_ meeting: MeetingLibrary.Meeting, template: String) async throws {
        guard let transcript = library.transcript(of: meeting), let target = meeting.notesURL ?? meeting.transcriptURL
        else { throw MeetingsError.noTranscript }
        let generator = try generator(promptURL: ProtocolTemplates.url(for: template))
        let diarized = transcript.range(of: #"\] [^:\n]+: "#, options: .regularExpression) != nil
        let notes = try await generator.generate(
            transcript: transcript, title: meeting.title, diarized: diarized,
            meetingStartTime: MeetingLibrary.date(fromFileName: meeting.id),
        )
        _ = try ProtocolGenerator.saveProtocol(
            notes, basename: target.deletingPathExtension().lastPathComponent, dir: target.deletingLastPathComponent(),
        )
        library.reload()
    }

    /// Answers `question` from the notes of every meeting, newest first, as
    /// many as fit in `budget` characters.
    func ask(_ question: String, budget: Int = 300_000) async throws -> String {
        var context = ""
        for meeting in library.meetings {
            guard let notes = library.notes(of: meeting) ?? library.transcript(of: meeting) else { continue }
            let entry = "<meeting title=\"\(meeting.title)\" date=\"\(meeting.date.formatted(date: .abbreviated, time: .shortened))\">\n\(notes)\n</meeting>\n\n"
            guard context.count + entry.count <= budget else { break }
            context += entry
        }
        guard !context.isEmpty else { throw MeetingsError.noMeetings }
        try? FileManager.default.createDirectory(at: AppPaths.dataDir, withIntermediateDirectories: true)
        try Self.askPrompt.write(to: Self.askPromptURL, atomically: true, encoding: .utf8)
        return try await generator(promptURL: Self.askPromptURL).generate(
            transcript: context + "Question: \(question)", title: "Ask", diarized: false, meetingStartTime: nil,
        )
    }

    /// Sends the tasks in `meeting`'s notes to Reminders. Returns how many.
    func addTasksToReminders(_ meeting: MeetingLibrary.Meeting) async throws -> Int {
        let items = ActionItem.parse(library.notes(of: meeting) ?? "")
        guard !items.isEmpty else { throw MeetingsError.noTasks }
        return try await calendar.addReminders(items, meetingTitle: meeting.title)
    }

    /// The people with a voice profile, most recently heard first.
    func people() -> [String] {
        SpeakerMatcher.factory(dbPath: pipeline.speakersDB, notifier: SilentNotifier())().allSpeakerNames()
    }

    /// The meetings whose transcript has a line spoken by `person`.
    func meetings(with person: String) -> [MeetingLibrary.Meeting] {
        library.meetings.filter { library.transcript(of: $0).map { Self.speaks(person, in: $0) } ?? false }
    }

    nonisolated static func speaks(_ person: String, in transcript: String) -> Bool {
        transcript.contains("] \(person): ") || transcript.hasPrefix("\(person): ")
            || transcript.contains("\n\(person): ")
    }

    private func generator(promptURL: URL) throws -> sending any ProtocolGenerating {
        guard let generator = pipeline.makeProtocolGenerator(promptURL: promptURL) else {
            throw MeetingsError.noModel
        }
        return generator
    }

    static let askPromptURL = AppPaths.dataDir.appendingPathComponent("ask_prompt.md")

    static let askPrompt = """
    You answer questions about the user's past meetings, using only the meeting notes below.
    Answer in the language of the question, in a few sentences or a short list.
    Name the meeting (title and date) each fact comes from. If the notes do not answer
    the question, say so in one sentence. Return only the answer.

    """

    enum MeetingsError: LocalizedError {
        case noTranscript, noMeetings, noTasks, noModel

        var errorDescription: String? {
            switch self {
            case .noTranscript: "This meeting has no transcript to write notes from."
            case .noMeetings: "There are no meeting notes yet."
            case .noTasks: "These notes list no tasks."
            case .noModel: "Choose a model for meeting notes in Settings → Meeting Notes first."
            }
        }
    }
}

extension CalendarMeeting {
    /// An in-person meeting with other people that started in the last two
    /// minutes and has not been announced. Online meetings are left to the
    /// detector, which sees the meeting app.
    static func startingInPerson(in events: [Self], at date: Date, except announced: Set<String>) -> Self? {
        events.first { event in
            !event.isOnline && !event.attendees.isEmpty && !announced.contains(event.id)
                && event.start <= date && date < event.start.addingTimeInterval(120)
        }
    }
}
