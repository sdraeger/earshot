import Foundation

/// Immutable identity of a Parakeet vocabulary configuration. The file revision
/// matters as much as the path: users commonly edit an existing terminology
/// file between meetings.
struct ParakeetVocabularyConfiguration: Equatable, Sendable {
    let path: String
    let bookmark: Data?
    let revision: WhisperVocabularyPrompt.FileRevision?
}
