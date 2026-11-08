@testable import Earshot
import XCTest

final class ProtocolTemplatesTests: XCTestCase {
    private func makeFolder() -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("templates-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        ProtocolTemplates.seedIfMissing(folder)
        return folder
    }

    func testSeedingWritesThePresetsAfterDefault() {
        let folder = makeFolder()

        let names = ProtocolTemplates.names(in: folder)

        XCTAssertEqual(names.first, ProtocolTemplates.defaultName)
        XCTAssertEqual(Set(names.dropFirst()), Set(ProtocolTemplates.presets.keys))
    }

    func testDefaultAndMissingTemplatesReadTheSettingsPrompt() {
        let folder = makeFolder()

        XCTAssertEqual(ProtocolTemplates.url(for: ProtocolTemplates.defaultName, in: folder), AppPaths.customPromptFile)
        XCTAssertEqual(ProtocolTemplates.url(for: "Gone", in: folder), AppPaths.customPromptFile)
        XCTAssertEqual(ProtocolTemplates.url(for: "Standup", in: folder).lastPathComponent, "Standup.md")
    }

    func testPresetsAskForTheTaskSectionTheRemindersReaderFinds() {
        for (name, prompt) in ProtocolTemplates.presets {
            XCTAssertTrue(prompt.contains("## Action Items"), name)
            XCTAssertTrue(prompt.hasSuffix("Transcript:"), name)
        }
    }

    func testTimestampedSpeakerLinesMarkATranscriptDiarized() {
        XCTAssertTrue(ProtocolGenerator.isDiarized("[00:05] Me: hi\n[1:02:03] Roman Li: ok"))
        XCTAssertFalse(ProtocolGenerator.isDiarized("[00:05] hello there\n[00:09] [Music]"))
    }

    func testTheFullTranscriptComesOffAgain() {
        let notes = "# Sync\n\n## Summary\nShipped."
        let full = ProtocolGenerator.withFullTranscript(notes, transcript: "[00:01] Ann: hi")

        XCTAssertTrue(MarkdownToNotionBlocks.hasFullTranscriptHeading(in: full))
        XCTAssertEqual(ProtocolGenerator.withoutFullTranscript(full), notes)
        XCTAssertEqual(ProtocolGenerator.withoutFullTranscript(notes), notes)
    }

    func testUserNotesGoAheadOfTheTranscript() {
        let input = ProtocolGenerator.input(transcript: "[00:01] Ann: hi", userNotes: "  budget is the blocker \n")

        XCTAssertTrue(input.contains("<user_notes>\nbudget is the blocker\n</user_notes>"))
        XCTAssertTrue(input.hasSuffix("[00:01] Ann: hi"))
        XCTAssertEqual(ProtocolGenerator.input(transcript: "t", userNotes: " \n"), "t")
        XCTAssertEqual(ProtocolGenerator.input(transcript: "t", userNotes: nil), "t")
    }
}
