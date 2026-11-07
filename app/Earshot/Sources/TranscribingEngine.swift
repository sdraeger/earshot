import Foundation

/// Common interface for transcription engine implementations (WhisperKit, Parakeet, …).
@MainActor
protocol TranscribingEngine: AnyObject {
    var modelState: EngineModelState { get }
    var downloadProgress: Double { get }

    /// Whether `transcribeSegments` returns per-utterance timestamps fine-grained
    /// enough to drive speaker diarization. WhisperKit and Parakeet do (default
    /// `true`). An engine that emits a single segment spanning the whole
    /// recording returns `false`, and the pipeline skips diarization with a
    /// warning (it would otherwise collapse the meeting onto one speaker).
    var providesTimestamps: Bool { get }

    /// The shortest input this engine will accept, in 16 kHz frames. The
    /// pipeline asks before handing a track over, so a track it would refuse is
    /// dropped with the rest of the recording kept rather than throwing the
    /// whole job away (issue #724).
    ///
    /// Default 1, which is the only floor that holds for every backend: a track
    /// with no frames at all has nothing to transcribe whatever the engine.
    /// Anything above that is one backend's rule and belongs to that backend, or
    /// a recording would be annotated as empty by a threshold its engine never
    /// had.
    var minimumAudioFrames: Int { get }

    func loadModel() async
    func transcribeSegments(audioPath: URL) async throws -> [TimestampedSegment]
}

extension TranscribingEngine {
    /// Most engines produce per-utterance timestamps; only the exceptions
    /// override this.
    var providesTimestamps: Bool {
        true
    }

    /// Only an engine with a documented floor of its own overrides this.
    var minimumAudioFrames: Int {
        1
    }
}

/// Engines that can transcribe an already-decoded `[Float]` buffer of
/// 16 kHz mono samples in memory — the API the live-transcription
/// pipeline feeds with VAD-bounded chunks straight off the audio tap.
///
/// Engines that can't do in-memory transcription (e.g. a chunk-batch-only
/// backend) simply don't conform. The caller's `as? StreamingTranscribingEngine`
/// cast is the static equivalent of
/// `TranscriptionEngineSetting.supportsLiveTranscription`.
@MainActor
protocol StreamingTranscribingEngine: TranscribingEngine {
    func transcribeSamples(_ samples: [Float]) async throws -> String
}

/// Errors every engine throws. The engine is named in the message, so the
/// job error says which model is missing.
enum TranscriptionError: LocalizedError {
    /// `reason` is the engine's `loadFailureReason` when the load that was just
    /// attempted failed, so the job error says why; nil where nothing is known.
    case modelNotLoaded(engine: String, reason: String? = nil)
    /// WhisperKit failed on a file. Kept whole rather than as its message, so
    /// `TranscriptionFailureScope` can still tell a bad file from a bad model.
    case transcriptionFailed(underlying: any Error)

    var errorDescription: String? {
        switch self {
        case let .modelNotLoaded(engine, reason): "\(engine) model not loaded" + (reason.map { ": \($0)" } ?? "")
        case let .transcriptionFailed(underlying): "WhisperKit transcription failed: \(underlying.localizedDescription)"
        }
    }
}
