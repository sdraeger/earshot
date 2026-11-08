import AppKit
import SwiftUI

/// The Meetings window: the meeting being recorded with its notepad, a
/// question box over all meetings, every meeting in the notes folder (newest
/// first and searchable) and the people with a voice profile, beside the
/// selected item.
struct MeetingsView: View {
    let meetings: MeetingsController
    let captions: LiveCaptionsState
    let isRecording: Bool
    /// Bumped when a job finishes, so a meeting that just got its notes appears.
    let completedJobCount: Int
    let onStopRecording: () -> Void

    @State private var selection: String?
    @State private var query = ""

    static let liveID = "live"
    static let askID = "ask"
    static let personPrefix = "person:"

    private var library: MeetingLibrary {
        meetings.library
    }

    private var shownMeetings: [MeetingLibrary.Meeting] {
        library.meetings.filter { library.matches($0, query: query) }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                if isRecording {
                    Label("Now recording", systemImage: "record.circle")
                        .foregroundStyle(.red)
                        .tag(Self.liveID)
                }
                Label("Ask your meetings", systemImage: "sparkle.magnifyingglass")
                    .tag(Self.askID)
                Section("Meetings") {
                    ForEach(shownMeetings) { meeting in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(meeting.title)
                                .lineLimit(1)
                            Text(meeting.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                        .tag(meeting.id)
                    }
                }
                peopleSection
            }
            .searchable(text: $query, placement: .sidebar, prompt: "Search meetings")
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Theme.paper)
        }
        .tint(Theme.accent)
        .frame(minWidth: 760, idealWidth: 940, minHeight: 480, idealHeight: 640)
        .onAppear {
            library.reload()
            if selection == nil { selection = isRecording ? Self.liveID : library.meetings.first?.id }
        }
        .onChange(of: completedJobCount) { _, _ in library.reload() }
        .onChange(of: isRecording) { _, recording in
            if recording { selection = Self.liveID } else if selection == Self.liveID { selection = nil }
        }
    }

    @ViewBuilder private var peopleSection: some View {
        let people = meetings.people()
        if !people.isEmpty {
            Section("People") {
                ForEach(people, id: \.self) { person in
                    Label(person, systemImage: "person")
                        .tag(Self.personPrefix + person)
                }
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if selection == Self.liveID, isRecording {
            LiveTranscriptView(meetings: meetings, captions: captions, onStopRecording: onStopRecording)
        } else if selection == Self.askID {
            AskView(meetings: meetings)
        } else if let person = selection?.dropFirst(Self.personPrefix.count), selection?.hasPrefix(Self.personPrefix) == true {
            PersonView(person: String(person), meetings: meetings.meetings(with: String(person))) { selection = $0 }
        } else if let meeting = library.meetings.first(where: { $0.id == selection }) {
            MeetingDetailView(meetings: meetings, meeting: meeting)
                .id(meeting.id)
        } else {
            ContentUnavailableView(
                "No meeting selected",
                systemImage: "ear",
                description: Text("Meetings you record appear here with their notes and transcript."),
            )
        }
    }
}

/// The notepad, and what is being said as the live transcript catches it.
private struct LiveTranscriptView: View {
    @Bindable var meetings: MeetingsController
    let captions: LiveCaptionsState
    let onStopRecording: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Live transcript")
                    .font(.system(size: 26, weight: .semibold, design: .serif))
                Spacer()
                Button("Stop Recording", action: onStopRecording)
                    .tint(.red)
            }
            .padding([.horizontal, .top], 28)
            .padding(.bottom, 12)

            notepad
            Divider()
            lines
        }
    }

    /// The user's own notes; the meeting notes are built around them.
    private var notepad: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $meetings.notepad)
                .font(.body)
                .scrollContentBackground(.hidden)
                .accessibilityIdentifier(A11yID.meetingNotepad)
            if meetings.notepad.isEmpty {
                Text("Your notes. Jot down what matters; the meeting notes are written around it.")
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: 120, idealHeight: 180, maxHeight: 260)
        .padding(.horizontal, 23)
        .padding(.bottom, 12)
    }

    private var lines: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if captions.transcript.isEmpty, pending.isEmpty {
                        Text("Waiting for speech. With live transcript off, the transcript appears when the meeting ends.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(captions.transcript.enumerated()), id: \.offset) { _, line in
                        TranscriptLine(speaker: line.speaker, text: line.text)
                    }
                    ForEach(pending, id: \.speaker) { line in
                        TranscriptLine(speaker: line.speaker, text: line.text)
                            .foregroundStyle(.secondary)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
                .textSelection(.enabled)
            }
            .onChange(of: captions.transcript.count) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
        }
    }

    /// Speech not yet finalized, per channel.
    private var pending: [(speaker: String, text: String)] {
        [(captions.micLabel, captions.hypothesisMic), (captions.appLabel, captions.hypothesisApp)]
            .filter { !$0.text.isEmpty }
    }
}

private struct TranscriptLine: View {
    let speaker: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(speaker)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Theme.accent)
            Text(text)
        }
    }
}

/// One finished meeting: its notes or transcript, and what can be done with it.
private struct MeetingDetailView: View {
    let meetings: MeetingsController
    let meeting: MeetingLibrary.Meeting

    private var library: MeetingLibrary {
        meetings.library
    }

    private enum Page: String, CaseIterable {
        case notes = "Notes"
        case transcript = "Transcript"
    }

    @State private var page: Page = .notes
    @State private var renaming = false
    @State private var newTitle = ""
    @State private var confirmingDelete = false
    @State private var working: String?
    @State private var message: String?

    private var pages: [Page] {
        [meeting.notesURL.map { _ in Page.notes }, meeting.transcriptURL.map { _ in Page.transcript }].compactMap(\.self)
    }

    private var shownPage: Page {
        pages.contains(page) ? page : pages.first ?? .notes
    }

    private var text: String {
        (shownPage == .notes ? library.notes(of: meeting) : library.transcript(of: meeting)) ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if let working {
                ProgressView(working).controlSize(.small).padding(.horizontal, 28).padding(.top, 12)
            }

            if pages.count > 1 {
                Picker("Show", selection: $page) {
                    ForEach(pages, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
                .padding(.horizontal, 28)
                .padding(.top, 16)
            }

            ScrollView {
                Group {
                    if shownPage == .notes {
                        NotesText(markdown: text)
                    } else {
                        Text(text)
                    }
                }
                .frame(maxWidth: 680, alignment: .leading)
                .textSelection(.enabled)
                .padding(28)
            }
        }
        .toolbar { toolbar }
        .alert("Rename meeting", isPresented: $renaming) {
            TextField("Title", text: $newTitle)
            Button("Rename") { try? library.rename(meeting, to: newTitle) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Move “\(meeting.title)” to the Trash?", isPresented: $confirmingDelete,
        ) {
            Button("Move to Trash", role: .destructive) { try? library.delete(meeting) }
        } message: {
            Text("Its notes and transcript go to the Trash, where you can restore them.")
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {}
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(meeting.title)
                .font(.system(size: 26, weight: .semibold, design: .serif))
                .textSelection(.enabled)
            Text(meeting.date.formatted(date: .complete, time: .shortened))
                .foregroundStyle(.secondary)
        }
        .padding([.horizontal, .top], 28)
    }

    /// Runs `action` with a progress line, then shows its result or error.
    private func run(_ title: String, _ action: @escaping () async throws -> String?) {
        working = title
        Task {
            do {
                message = try await action()
            } catch {
                message = error.localizedDescription
            }
            working = nil
        }
    }

    /// Rewrite the notes with a template, and send their tasks to Reminders.
    @ViewBuilder private var noteActions: some View {
        Menu {
            ForEach(ProtocolTemplates.names(), id: \.self) { template in
                Button(template) {
                    run("Writing notes with \(template)…") {
                        try await meetings.regenerate(meeting, template: template)
                        page = .notes
                        return nil
                    }
                }
            }
        } label: { Label("Rewrite Notes", systemImage: "wand.and.stars") }
            .help("Write the notes again with a template")
            .disabled(meeting.transcriptURL == nil || working != nil)
        Button {
            run("Adding tasks to Reminders…") {
                let count = try await meetings.addTasksToReminders(meeting)
                return "Added \(count) task\(count == 1 ? "" : "s") to the Earshot list in Reminders."
            }
        } label: { Label("Add Tasks to Reminders", systemImage: "checklist") }
            .help("Add the tasks in these notes to Reminders")
            .disabled(meeting.notesURL == nil || working != nil)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            noteActions
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } label: { Label("Copy", systemImage: "doc.on.doc") }
                .help("Copy the \(shownPage.rawValue.lowercased())")
            Button {
                if let url = shownPage == .notes ? meeting.notesURL : meeting.transcriptURL {
                    NSWorkspace.shared.open(url)
                }
            } label: { Label("Open", systemImage: "arrow.up.forward.app") }
                .help("Open in its default app")
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([meeting.notesURL, meeting.transcriptURL].compactMap(\.self))
            } label: { Label("Show in Finder", systemImage: "folder") }
                .help("Show in Finder")
            Button {
                newTitle = meeting.title
                renaming = true
            } label: { Label("Rename", systemImage: "pencil") }
                .help("Rename")
                .disabled(meeting.notesURL == nil)
            Button(role: .destructive) {
                confirmingDelete = true
            } label: { Label("Delete", systemImage: "trash") }
                .help("Move to Trash")
        }
    }
}

/// Meeting notes Markdown, set line by line: serif headings, bullets, and
/// inline emphasis through `AttributedString`.
private struct NotesText: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(markdown.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                row(line.trimmingCharacters(in: .whitespaces))
            }
        }
    }

    @ViewBuilder
    private func row(_ line: String) -> some View {
        if line.hasPrefix("# ") {
            Text(inline(String(line.dropFirst(2))))
                .font(.system(.title2, design: .serif, weight: .semibold))
        } else if line.hasPrefix("## ") {
            Text(inline(String(line.dropFirst(3))))
                .font(.system(.title3, design: .serif, weight: .semibold))
                .padding(.top, 8)
        } else if line.hasPrefix("### ") {
            Text(inline(String(line.dropFirst(4))))
                .font(.headline)
        } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(Theme.accent)
                Text(inline(String(line.dropFirst(2))))
            }
        } else if line == "---" {
            Divider()
        } else if !line.isEmpty {
            Text(inline(line))
        }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}

/// A question about every meeting, answered from their notes.
private struct AskView: View {
    let meetings: MeetingsController

    @State private var question = ""
    @State private var asked = ""
    @State private var answer = ""
    @State private var asking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ask your meetings")
                .font(.system(size: 26, weight: .semibold, design: .serif))
            TextField("What did we decide about the launch date?", text: $question)
                .textFieldStyle(.roundedBorder)
                .onSubmit(ask)
                .disabled(asking)
                .accessibilityIdentifier(A11yID.askField)
            if asking {
                ProgressView("Reading your meetings…").controlSize(.small)
            }
            if !answer.isEmpty {
                answerView
            }
            Spacer(minLength: 0)
        }
        .padding(28)
    }

    private var answerView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(asked).font(.headline)
                NotesText(markdown: answer)
            }
            .frame(maxWidth: 680, alignment: .leading)
            .textSelection(.enabled)
        }
    }

    private func ask() {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !asking else { return }
        asking = true
        Task {
            do {
                answer = try await meetings.ask(question)
            } catch {
                answer = error.localizedDescription
            }
            asked = question
            asking = false
        }
    }
}

/// The meetings one person spoke in.
private struct PersonView: View {
    let person: String
    let meetings: [MeetingLibrary.Meeting]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(person)
                .font(.system(size: 26, weight: .semibold, design: .serif))
            Text(meetings.isEmpty ? "No meeting in this folder has \(person) speaking." : "Spoke in \(meetings.count) meeting\(meetings.count == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
            List(meetings) { meeting in
                Button {
                    onSelect(meeting.id)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(meeting.title)
                        Text(meeting.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .scrollContentBackground(.hidden)
        }
        .padding(28)
    }
}
