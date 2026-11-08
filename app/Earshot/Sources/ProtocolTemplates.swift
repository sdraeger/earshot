import Foundation

/// Named meeting-notes templates: "Default" (the custom prompt from Settings,
/// or the built-in one) plus one Markdown prompt file per template in
/// `folder`. The folder is seeded with `presets` the first time it is read, so
/// the presets are files the user can edit, delete or copy into new ones.
enum ProtocolTemplates {
    static let defaultName = "Default"

    /// Created with the presets the first time it is read.
    static let folder: URL = {
        let folder = AppPaths.dataDir.appendingPathComponent("templates", isDirectory: true)
        seedIfMissing(folder)
        return folder
    }()

    /// Every template, "Default" first, then the files in `folder` by name.
    static func names(in folder: URL = folder) -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let names = files.filter { $0.pathExtension == "md" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return [defaultName] + names.filter { $0 != defaultName }
    }

    /// The prompt file for `name`. "Default" and a name without a file read as
    /// the Settings prompt, which `ProtocolGenerator.loadPrompt` falls back
    /// from to the built-in prompt when it is absent.
    static func url(for name: String, in folder: URL = folder) -> URL {
        let file = folder.appendingPathComponent("\(name).md")
        guard name != defaultName, FileManager.default.fileExists(atPath: file.path) else {
            return AppPaths.customPromptFile
        }
        return file
    }

    static func seedIfMissing(_ folder: URL) {
        guard !FileManager.default.fileExists(atPath: folder.path) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, prompt) in presets {
            try? prompt.write(to: folder.appendingPathComponent("\(name).md"), atomically: true, encoding: .utf8)
        }
    }

    private static let header = """
    Return ONLY the finished Markdown document in {LANGUAGE}, with no text before or after it.
    The first line is `# ` followed by a short, specific title for the meeting.
    **Date:** {MEETING_DATE} · **Time:** {MEETING_TIME}

    """

    private static let actionItems = """
    ## Action Items
    - [Task] — [Owner or open] — [Due date as YYYY-MM-DD, or open]
    """

    static let presets: [String: String] = [
        "One-on-one": header + """
        Write notes for a one-on-one meeting with these sections:

        ## Updates
        ## Feedback
        ## Blockers and support needed
        ## Career and growth
        \(actionItems)

        Leave out a section with nothing in it. Do not include the transcript.

        Transcript:
        """,
        "Standup": header + """
        Write standup notes. For each person, one `###` heading with their name and three bullet lists:
        Done, Next, Blocked. Then:

        \(actionItems)

        Keep every bullet to one line. Do not include the transcript.

        Transcript:
        """,
        "Interview": header + """
        Write notes for a job or research interview with these sections:

        ## Candidate summary
        ## Strengths (with evidence from what was said)
        ## Concerns (with evidence from what was said)
        ## Questions asked and answers
        \(actionItems)

        Quote nothing longer than a sentence. Do not include the transcript.

        Transcript:
        """,
        "Lecture": header + """
        Write study notes for a lecture or talk with these sections:

        ## Key ideas
        ## Definitions and formulas
        ## Examples
        ## Questions raised
        \(actionItems)

        Do not include the transcript.

        Transcript:
        """,
    ]
}
