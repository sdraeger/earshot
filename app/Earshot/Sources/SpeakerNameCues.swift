import Foundation
import NaturalLanguage

/// Estimates names for speakers no voice profile recognized, from what is said
/// in the meeting (English and German):
///
/// - a speaker introducing themselves ("I'm Sarah", "ich bin Tom", "Sarah here")
///   scores `introductionWeight` for that speaker;
/// - a name addressed at the start or end of a turn ("Sarah, what do you
///   think?") scores `addressWeight` for the next speaker, and a name thanked
///   ("Thanks, Sarah") scores it for the previous one. Either takes
///   `addressWeight` off the speaker who said it, who is not the one addressed.
///
/// A captured word counts only when the NaturalLanguage name tagger reads it as
/// a person's name in its turn, or when it matches a Teams participant. German
/// capitalizes every noun, so "ich bin Entwickler" would otherwise name someone
/// "Entwickler". Names go out highest score first, each name and speaker at
/// most once, and only from `threshold` up: one introduction, or two
/// consistent address cues. A speaker the meeting never names keeps no estimate.
enum SpeakerNameCues {
    struct Estimate: Equatable {
        let name: String
        /// Why this name, for the naming dialog.
        let clue: String
    }

    static let introductionWeight = 3.0
    static let addressWeight = 1.0
    static let threshold = 2.0

    /// `segments` carry raw diarizer labels as `speaker`; only `unnamed` labels
    /// get estimates, and names in `taken` (already matched by voice) are never
    /// given out again.
    static func estimate(
        segments: [TimestampedSegment],
        unnamed: Set<String>,
        taken: Set<String>,
        participants: [String],
    ) -> [String: Estimate] {
        let turns = turns(of: segments)
        var score: [String: [String: Double]] = [:]
        var introduction: [String: [String: String]] = [:]
        var addressCount: [String: [String: Int]] = [:]
        let takenKeys = Set(taken.flatMap { [$0.lowercased(), firstToken($0).lowercased()] })

        func canonical(_ word: String, in text: String) -> String? {
            let name = participants.first { firstToken($0).caseInsensitiveCompare(word) == .orderedSame }
                ?? (isPersonalName(word, in: text) ? word : nil)
            guard let name, !takenKeys.contains(name.lowercased()), !takenKeys.contains(word.lowercased()) else { return nil }
            return name
        }

        for (index, turn) in turns.enumerated() {
            let introduced = matches(of: introductionPatterns, in: turn.text)
            let thanked = matches(of: thanksPatterns, in: turn.text)
            // "Thanks, Sarah." also reads as a name at the end of a turn; the
            // thanks points back, so it is not counted forward as well.
            let claimed = Set((introduced + thanked).map(\.word))
            for (word, phrase) in introduced {
                guard let name = canonical(word, in: turn.text) else { continue }
                score[turn.speaker, default: [:]][name, default: 0] += introductionWeight
                introduction[turn.speaker, default: [:]][name] = phrase
            }
            let addressed: [(word: String, target: Int?)] =
                matches(of: addressPatterns, in: turn.text).filter { !claimed.contains($0.word) }
                    .map { ($0.word, nextSpeakerTurn(after: index, in: turns)) }
                    + thanked.map { ($0.word, previousSpeakerTurn(before: index, in: turns)) }
            for (word, target) in addressed {
                guard let name = canonical(word, in: turn.text) else { continue }
                score[turn.speaker, default: [:]][name, default: 0] -= addressWeight
                guard let target else { continue }
                let speaker = turns[target].speaker
                score[speaker, default: [:]][name, default: 0] += addressWeight
                addressCount[speaker, default: [:]][name, default: 0] += 1
            }
        }

        let candidates = score
            .filter { unnamed.contains($0.key) }
            .flatMap { speaker, names in names.map { (speaker: speaker, name: $0.key, score: $0.value) } }
            .filter { $0.score >= threshold }
            .sorted { ($0.score, $1.speaker, $1.name) > ($1.score, $0.speaker, $0.name) }

        var result: [String: Estimate] = [:]
        var used: Set<String> = []
        for candidate in candidates where result[candidate.speaker] == nil && !used.contains(candidate.name) {
            let clue = introduction[candidate.speaker]?[candidate.name].map { "Introduced themselves: “\($0)”" }
                ?? "Addressed as \(candidate.name) \(addressCount[candidate.speaker]?[candidate.name] ?? 0)×"
            result[candidate.speaker] = Estimate(name: candidate.name, clue: clue)
            used.insert(candidate.name)
        }
        return result
    }

    /// What a meeting offers beyond the voices: its transcript (raw diarizer
    /// labels as speakers) and which labels are voices on the local microphone.
    struct Context {
        var transcript: [TimestampedSegment] = []
        var micLabels: Set<String> = []
        /// The user's name for themselves at the microphone; empty assigns nothing.
        var micName = ""
    }

    /// The best name per speaker: a voice match stays, every speaker still
    /// unnamed (name == label) gets its estimate from the conversation, and the
    /// voice that speaks most on the microphone gets `micName` when no
    /// microphone voice was recognized and the conversation did not name it.
    /// Returns the mapping and, per estimated label, why.
    static func refine(
        _ mapping: [String: String], context: Context,
        participants: [String], speakingTimes: [String: TimeInterval],
    ) -> (mapping: [String: String], clues: [String: String]) {
        let unnamed = Set(mapping.filter { $0.key == $0.value }.keys)
        let guesses = estimate(
            segments: context.transcript, unnamed: unnamed,
            taken: Set(mapping.filter { $0.key != $0.value }.values), participants: participants,
        )
        var mapping = mapping
        var clues = guesses.mapValues(\.clue)
        for (label, guess) in guesses {
            mapping[label] = guess.name
        }
        let micRecognized = context.micLabels.contains { unnamed.contains($0) == false }
        if !context.micName.isEmpty, !micRecognized, !mapping.values.contains(context.micName),
           let own = context.micLabels.max(by: { (speakingTimes[$0] ?? 0, $1) < (speakingTimes[$1] ?? 0, $0) }),
           mapping[own] == own {
            mapping[own] = context.micName
            clues[own] = "Speaks most on your microphone"
        }
        return (mapping, clues)
    }

    // MARK: - Turns

    struct Turn {
        let speaker: String
        let text: String
    }

    /// Consecutive segments of one speaker joined into one turn, in time order.
    static func turns(of segments: [TimestampedSegment]) -> [Turn] {
        var turns: [Turn] = []
        for segment in segments.filter({ !$0.suppressed }).sorted(by: { $0.start < $1.start }) {
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if let last = turns.last, last.speaker == segment.speaker {
                turns[turns.count - 1] = Turn(speaker: last.speaker, text: last.text + " " + text)
            } else {
                turns.append(Turn(speaker: segment.speaker, text: text))
            }
        }
        return turns
    }

    private static func nextSpeakerTurn(after index: Int, in turns: [Turn]) -> Int? {
        turns.indices.dropFirst(index + 1).first { turns[$0].speaker != turns[index].speaker }
    }

    private static func previousSpeakerTurn(before index: Int, in turns: [Turn]) -> Int? {
        turns.indices.prefix(index).last { turns[$0].speaker != turns[index].speaker }
    }

    // MARK: - Patterns

    /// A capitalized word, not a possessive ("Sarah's" names Sarah's thing, not Sarah).
    private static let name = #"(\p{Lu}[\p{L}\-]+)(?!['’]s)\b"#
    private static let lead = #"^\W*(?:(?:hi|hey|hello|hallo|so|okay|ok|also|and|und|well|yes|ja|gut)\W+)?"#

    static let introductionPatterns = compile([
        #"\b(?i:my name is|my name's|i am|i'm|this is|it's|call me)\s+"# + name,
        #"\b(?i:ich bin|ich heiße|ich heisse|mein name ist|hier ist|hier spricht)\s+"# + name,
        lead + name + #"\s+(?i:here|hier)\b"#,
    ])
    static let addressPatterns = compile([
        lead + name + #"\s*[,:]"#,
        #",\s*"# + name + #"\s*[?!.]*\s*$"#,
    ])
    static let thanksPatterns = compile([
        #"\b(?i:thanks|thank you|danke(?: schön| dir| ihnen)?|vielen dank)\W+"# + name,
    ])

    private static func compile(_ patterns: [String]) -> [NSRegularExpression] {
        // swiftlint:disable:next force_try
        patterns.map { try! NSRegularExpression(pattern: $0, options: [.anchorsMatchLines]) }
    }

    /// Each match's captured name and the whole matched phrase.
    private static func matches(of patterns: [NSRegularExpression], in text: String) -> [(word: String, phrase: String)] {
        let range = NSRange(text.startIndex..., in: text)
        return patterns.flatMap { pattern in
            pattern.matches(in: text, range: range).compactMap { match in
                guard let word = Range(match.range(at: 1), in: text), let phrase = Range(match.range, in: text) else { return nil }
                return (String(text[word]), text[phrase].trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)))
            }
        }
    }

    // MARK: - Names

    private static func firstToken(_ name: String) -> String {
        String(name.split(separator: " ").first ?? Substring(name))
    }

    /// Whether the name tagger reads `word` as (part of) a person's name in `text`.
    static func isPersonalName(_ word: String, in text: String) -> Bool {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var found = false
        tagger.enumerateTags(
            in: text.startIndex ..< text.endIndex, unit: .word, scheme: .nameType,
            options: [.omitPunctuation, .omitWhitespace, .joinNames],
        ) { tag, range in
            if tag == .personalName, text[range].split(separator: " ").contains(Substring(word)) {
                found = true
                return false
            }
            return true
        }
        return found
    }
}
