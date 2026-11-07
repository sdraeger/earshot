@testable import Earshot
import XCTest

final class SpeakerNameCuesTests: XCTestCase {
    /// One segment per line, `speaker: text`, one second apart.
    private func segments(_ lines: [(String, String)]) -> [TimestampedSegment] {
        lines.enumerated().map { index, line in
            TimestampedSegment(start: Double(index), end: Double(index) + 1, text: line.1, speaker: line.0)
        }
    }

    private func names(
        _ lines: [(String, String)],
        unnamed: Set<String> = ["A", "B", "C"],
        taken: Set<String> = [],
        participants: [String] = [],
    ) -> [String: String] {
        SpeakerNameCues.estimate(
            segments: segments(lines), unnamed: unnamed, taken: taken, participants: participants,
        ).mapValues(\.name)
    }

    func testSelfIntroductionNamesTheSpeaker() {
        let result = SpeakerNameCues.estimate(
            segments: segments([("A", "Hi everyone, I'm Sarah Miller from the design team."), ("B", "Welcome.")]),
            unnamed: ["A", "B"], taken: [], participants: [],
        )
        XCTAssertEqual(result["A"]?.name, "Sarah")
        XCTAssertEqual(result["A"]?.clue, "Introduced themselves: “I'm Sarah”")
        XCTAssertNil(result["B"], "a speaker the meeting never names gets no estimate")
    }

    func testGermanIntroductionNamesTheSpeaker() {
        XCTAssertEqual(names([("A", "Hallo zusammen, hier ist Thomas."), ("B", "Hallo Thomas.")])["A"], "Thomas")
    }

    func testGermanNounAfterIchBinIsNotAName() {
        XCTAssertNil(names([("A", "Ich bin Entwickler im Backend-Team.")])["A"])
    }

    func testOneAddressIsNotEnough() {
        XCTAssertNil(names([("A", "Sarah, what do you think?"), ("B", "I agree.")])["B"])
    }

    func testRepeatedAddressNamesTheNextSpeaker() {
        let result = names([
            ("A", "Sarah, what do you think?"),
            ("B", "Looks good to me."),
            ("A", "Can you take the next item, Sarah?"),
            ("B", "Sure."),
        ])
        XCTAssertEqual(result["B"], "Sarah")
        XCTAssertNil(result["A"], "the one doing the addressing is not Sarah")
    }

    func testThanksPointsBackToThePreviousSpeaker() {
        let result = names([
            ("B", "That's all from my side."),
            ("A", "Thanks, Tom."),
            ("B", "One more thing."),
            ("A", "Thank you Tom."),
        ])
        XCTAssertEqual(result["B"], "Tom")
    }

    func testVoiceMatchedNamesAreNotGivenOutAgain() {
        XCTAssertNil(names([("A", "I'm Sarah.")], taken: ["Sarah Miller"])["A"])
    }

    func testParticipantRosterGivesTheFullName() {
        XCTAssertEqual(names([("A", "Hi, I'm Priya.")], participants: ["Priya Raman"])["A"], "Priya Raman")
    }

    func testOnlyUnnamedSpeakersGetEstimates() {
        XCTAssertTrue(names([("A", "I'm Sarah.")], unnamed: ["B"]).isEmpty)
    }

    func testEachNameGoesToOneSpeaker() {
        let result = names([("A", "I'm Sarah."), ("B", "I'm Sarah too, funnily enough.")])
        XCTAssertEqual(result.values.filter { $0 == "Sarah" }.count, 1)
    }

    // MARK: - refine

    private let identity = ["R_SPEAKER_0": "R_SPEAKER_0", "M_SPEAKER_0": "M_SPEAKER_0", "M_SPEAKER_1": "M_SPEAKER_1"]
    private let times: [String: TimeInterval] = ["R_SPEAKER_0": 300, "M_SPEAKER_0": 120, "M_SPEAKER_1": 400]

    func testMostSpokenMicVoiceGetsTheMicName() {
        let refined = SpeakerNameCues.refine(
            identity,
            context: .init(micLabels: ["M_SPEAKER_0", "M_SPEAKER_1"], micName: "Simon"),
            participants: [], speakingTimes: times,
        )
        XCTAssertEqual(refined.mapping["M_SPEAKER_1"], "Simon")
        XCTAssertEqual(refined.mapping["M_SPEAKER_0"], "M_SPEAKER_0", "a second voice in the room keeps its own identity")
        XCTAssertEqual(refined.mapping["R_SPEAKER_0"], "R_SPEAKER_0", "remote voices never get the mic name")
        XCTAssertEqual(refined.clues["M_SPEAKER_1"], "Speaks most on your microphone")
    }

    func testRecognizedMicVoiceKeepsTheMicNameUnused() {
        var mapping = identity
        mapping["M_SPEAKER_0"] = "Simon Dräger"
        let refined = SpeakerNameCues.refine(
            mapping,
            context: .init(micLabels: ["M_SPEAKER_0", "M_SPEAKER_1"], micName: "Me"),
            participants: [], speakingTimes: times,
        )
        XCTAssertEqual(refined.mapping["M_SPEAKER_0"], "Simon Dräger")
        XCTAssertEqual(refined.mapping["M_SPEAKER_1"], "M_SPEAKER_1")
        XCTAssertTrue(refined.clues.isEmpty)
    }

    func testConversationNamesWinOverTheMicDefault() {
        let refined = SpeakerNameCues.refine(
            identity,
            context: .init(
                transcript: segments([("M_SPEAKER_1", "Hi all, I'm Simon."), ("R_SPEAKER_0", "Hi, my name is Anna.")]),
                micLabels: ["M_SPEAKER_0", "M_SPEAKER_1"], micName: "Me",
            ),
            participants: [], speakingTimes: times,
        )
        XCTAssertEqual(refined.mapping["M_SPEAKER_1"], "Simon")
        XCTAssertEqual(refined.mapping["R_SPEAKER_0"], "Anna")
        XCTAssertEqual(refined.mapping["M_SPEAKER_0"], "M_SPEAKER_0", "the default goes only to the most-spoken voice")
    }

    func testEmptyMicNameNamesNoMicVoice() {
        let refined = SpeakerNameCues.refine(
            identity, context: .init(micLabels: ["M_SPEAKER_1"], micName: ""), participants: [], speakingTimes: times,
        )
        XCTAssertEqual(refined.mapping, identity)
    }

    func testSuppressedSegmentsAreIgnored() {
        var lines = segments([("A", "I'm Sarah.")])
        lines[0].suppressed = true
        XCTAssertTrue(SpeakerNameCues.estimate(segments: lines, unnamed: ["A"], taken: [], participants: []).isEmpty)
    }
}
