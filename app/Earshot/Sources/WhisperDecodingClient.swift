import WhisperKit

/// The narrow decode boundary used by `WhisperKitEngine`. Production forwards
/// to WhisperKit; tests capture the exact options that each public engine flow
/// hands to this boundary without loading a CoreML model.
@MainActor
protocol WhisperDecodingClient: AnyObject {
    var tokenizer: (any WhisperTokenizer)? { get }

    /// One `Result` per path, in order, so a failure keeps WhisperKit's error.
    func transcribeFile(
        audioPaths: [String],
        decodeOptions: DecodingOptions,
    ) async -> [Result<[TranscriptionResult], any Error>]

    func transcribeSamples(
        _ samples: [Float],
        decodeOptions: DecodingOptions,
    ) async throws -> [TranscriptionResult]
}

extension WhisperKit: WhisperDecodingClient {
    func transcribeFile(
        audioPaths: [String],
        decodeOptions: DecodingOptions,
    ) async -> [Result<[TranscriptionResult], any Error>] {
        await transcribeWithResults(audioPaths: audioPaths, decodeOptions: decodeOptions)
    }

    func transcribeSamples(
        _ samples: [Float],
        decodeOptions: DecodingOptions,
    ) async throws -> [TranscriptionResult] {
        try await transcribe(audioArray: samples, decodeOptions: decodeOptions)
    }
}
