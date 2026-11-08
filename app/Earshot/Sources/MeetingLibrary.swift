import AppKit
import Foundation
import Observation

/// The meetings in the notes folder, for the Meetings window: each meeting's
/// notes (`.md`) and transcript (`.txt`), paired by the file name the pipeline
/// gives both, newest first.
@Observable
@MainActor
final class MeetingLibrary {
    struct Meeting: Identifiable, Equatable {
        /// The shared file name, `yyyyMMdd_HHmm_title_shortid`.
        let id: String
        let title: String
        let date: Date
        let notesURL: URL?
        let transcriptURL: URL?
    }

    private(set) var meetings: [Meeting] = []
    /// File contents read since the last `reload`, so search and the People
    /// view read each file once.
    @ObservationIgnored private var texts: [URL: String] = [:]
    /// The `protocols` folder under the current output folder, read on every
    /// reload so a changed output folder shows its own meetings.
    private let folder: () -> URL

    init(folder: @escaping () -> URL) {
        self.folder = folder
    }

    func reload() {
        texts = [:]
        let folder = folder()
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.creationDateKey],
        )) ?? []
        var byName: [String: (notes: URL?, transcript: URL?)] = [:]
        for file in files {
            let name = file.deletingPathExtension().lastPathComponent
            switch file.pathExtension {
            case "md": byName[name, default: (nil, nil)].notes = file
            case "txt": byName[name, default: (nil, nil)].transcript = file
            default: continue
            }
        }
        meetings = byName.map { name, files in
            let notes = files.notes.flatMap(text(at:))
            return Meeting(
                id: name,
                title: notes.flatMap { ProtocolGenerator.extractTitle(from: $0) } ?? Self.title(fromFileName: name),
                date: Self.date(fromFileName: name) ?? Self.creationDate(of: files.notes ?? files.transcript),
                notesURL: files.notes,
                transcriptURL: files.transcript,
            )
        }
        .sorted { $0.date > $1.date }
    }

    func notes(of meeting: Meeting) -> String? {
        meeting.notesURL.flatMap(text(at:))
    }

    func transcript(of meeting: Meeting) -> String? {
        meeting.transcriptURL.flatMap(text(at:))
    }

    /// What the user typed during the meeting, when they typed anything.
    func userNotes(of meeting: Meeting) -> String? {
        text(at: userNotesURL(of: meeting))
    }

    private func userNotesURL(of meeting: Meeting) -> URL {
        folder().appendingPathComponent(meeting.id).appendingPathExtension(ProtocolGenerator.userNotesExtension)
    }

    private func text(at url: URL) -> String? {
        if let text = texts[url] { return text }
        let text = try? String(contentsOf: url, encoding: .utf8)
        texts[url] = text
        return text
    }

    /// Whether the title or either file's text contains `query`, ignoring case.
    func matches(_ meeting: Meeting, query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return [meeting.title, notes(of: meeting) ?? "", transcript(of: meeting) ?? ""]
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }

    /// Renames the meeting by rewriting its notes' title heading. The files
    /// keep their names: the pipeline's jobs and the menu point at them.
    func rename(_ meeting: Meeting, to title: String) throws {
        guard let url = meeting.notesURL else { return }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let notes = try String(contentsOf: url, encoding: .utf8)
        try Self.retitled(notes, to: title).write(to: url, atomically: true, encoding: .utf8)
        reload()
    }

    /// Moves the meeting's notes, transcript and typed notes to the Trash.
    func delete(_ meeting: Meeting) throws {
        let typed = userNotesURL(of: meeting)
        let typedIfAny = FileManager.default.fileExists(atPath: typed.path) ? typed : nil
        for url in [meeting.notesURL, meeting.transcriptURL, typedIfAny].compactMap(\.self) {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        reload()
    }

    /// `notes` with its first `# ` heading replaced by `title`, or the heading
    /// added on top when it has none.
    nonisolated static func retitled(_ notes: String, to title: String) -> String {
        var lines = notes.components(separatedBy: "\n")
        if let index = lines.firstIndex(where: { $0.hasPrefix("# ") }) {
            lines[index] = "# \(title)"
            return lines.joined(separator: "\n")
        }
        return "# \(title)\n\n" + notes
    }

    /// The title part of `yyyyMMdd_HHmm_title_shortid`, spaced out.
    nonisolated static func title(fromFileName name: String) -> String {
        var parts = name.split(separator: "_").map(String.init)
        if parts.count >= 2, parts[0].count == 8, parts[1].count == 4, parts[0].allSatisfy(\.isNumber) {
            parts.removeFirst(2)
        }
        if parts.count > 1, let last = parts.last, last.count == 8, last.allSatisfy(\.isHexDigit) {
            parts.removeLast()
        }
        let title = parts.joined(separator: " ")
        return title.isEmpty ? name : title.prefix(1).uppercased() + title.dropFirst()
    }

    nonisolated static func date(fromFileName name: String) -> Date? {
        guard name.count >= 13 else { return nil }
        return fileNameDateFormatter.date(from: String(name.prefix(13)))
    }

    nonisolated private static let fileNameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static func creationDate(of url: URL?) -> Date {
        (try? url?.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
    }
}
