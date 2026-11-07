import FluidAudio
import Foundation
import os.log

private let logger = Logger(subsystem: AppPaths.logSubsystem, category: "ParakeetEngine")

/// Transcription engine backed by NVIDIA Parakeet TDT v3 via FluidAudio CoreML.
///
/// Supports 25 European languages with ~10× faster transcription than Whisper Large v3
/// and lower hallucination risk. Model download is ~50 MB (CoreML, same infrastructure
/// as the FluidAudio diarization models).
@MainActor
@Observable
final class ParakeetEngine: TranscribingEngine, StreamingTranscribingEngine {
    private(set) var modelState: EngineModelState = .unloaded
    private(set) var downloadProgress: Double = 0

    /// FluidAudio refuses anything shorter with
    /// `Invalid audio data provided. Must be at least 300ms of 16kHz audio`.
    /// Taken from its own constant so the threshold the pipeline checks and the
    /// one the engine enforces cannot drift apart, and stated here rather than
    /// in the pipeline so no other backend inherits a floor it does not have.
    var minimumAudioFrames: Int {
        ASRConstants.minimumRequiredSamples(forSampleRate: AudioConstants.targetSampleRate)
    }

    /// Path to a custom vocabulary file for CTC boosting. A change while the
    /// model is loaded is applied to the next transcription without restart.
    var customVocabularyPath: String = "" {
        didSet {
            guard customVocabularyPath != oldValue else { return }
            invalidateVocabularyConfiguration()
        }
    }

    var customVocabularyBookmark: Data? {
        didSet {
            guard customVocabularyBookmark != oldValue else { return }
            invalidateVocabularyConfiguration()
        }
    }

    /// Optional ISO 639-1 language hint. Empty/nil = auto-detect (FluidAudio's
    /// v3 TDT decoder picks the script freely, which can drift Cyrillic ↔ Latin
    /// on multi-script audio). Codes that don't match `FluidAudio.Language`
    /// fall back to nil. Set from `AppSettings.parakeetLanguageOrNil`.
    var language: String?

    /// Maps `language` to the FluidAudio enum at call time. Kept private so
    /// the public surface stays `String?` and AppState doesn't need to import
    /// FluidAudio.
    private var fluidLanguageHint: Language? {
        guard let language, !language.isEmpty else { return nil }
        return Language(rawValue: language)
    }

    private var asrManager: AsrManager?
    private let modelLoad = SingleFlight<Void>()

    // CTC vocabulary boosting state
    private struct VocabularyBooster {
        let context: CustomVocabularyContext
        let spotter: CtcKeywordSpotter
        let rescorer: VocabularyRescorer
    }

    private var vocabularyBooster: VocabularyBooster?

    // The CTC bridge is replaceable only in debug/test builds, where loading
    // production CTC models would make lifecycle tests impractical.
    #if DEBUG
        private var vocabularyPreparationOverride: (([String]) async throws -> Void)?
        private var fileTranscriptionOverride: ((URL) async throws -> ASRResult)?
        private var sampleTranscriptionOverride: (([Float]) async throws -> ASRResult)?
        private var modelLoadOverride: (@MainActor () async -> Void)?
    #endif

    /// The exact vocabulary revision being prepared or already handled, ready
    /// or not. Unlike a path it changes when a user edits the file. A revision
    /// that failed stays handled: retrying it for every recording window only
    /// adds repeated I/O and log noise, and an edit makes it a new revision.
    private var handledVocabulary: ParakeetVocabularyConfiguration?
    /// Bumped when Settings change, so a preparation that resumes after a
    /// model download does not adopt a booster for a selection now gone.
    private var vocabularyGeneration = 0

    private func invalidateVocabularyConfiguration() {
        vocabularyGeneration &+= 1
        handledVocabulary = nil
        // Do not rescore a new recording with terms from the file that was just
        // replaced. `ensureVocabularyConfiguration()` prepares the new booster
        // before the next decode begins.
        vocabularyBooster = nil
    }

    func loadModel() async {
        await modelLoad.run { [self] in await performLoad() }
    }

    private func performLoad() async {
        #if DEBUG
            if let modelLoadOverride {
                await modelLoadOverride()
                return
            }
        #endif
        modelState = .downloading
        downloadProgress = 0
        do {
            let models = try await AsrModels.downloadAndLoad { [weak self] progress in
                Task { @MainActor in
                    self?.downloadProgress = progress.fractionCompleted
                }
            }
            modelState = .loading
            downloadProgress = 1.0
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            asrManager = manager
            modelState = .loaded
        } catch {
            logger.error("Parakeet model load failed: \(error.localizedDescription, privacy: .public)")
            modelState = .unloaded
            downloadProgress = 0
        }
    }

    /// Ensure model is loaded, loading it if necessary. The load is started
    /// or joined even by a caller already cancelled, so it is under way for
    /// the next job, but a cancelled caller stops waiting for it at once.
    private func ensureModel() async throws {
        if asrManager != nil { return }
        #if DEBUG
            if fileTranscriptionOverride != nil, sampleTranscriptionOverride != nil { return }
        #endif
        logger.info("Parakeet: model not loaded, loading…")
        try await modelLoad.runUnlessCancelled { [self] in await performLoad() }
        guard asrManager != nil else {
            logger.error("Parakeet: model load FAILED, state=\(String(describing: self.modelState), privacy: .public)")
            throw TranscriptionError.modelNotLoaded(engine: "Parakeet")
        }
        logger.info("Parakeet: model loaded successfully")
    }

    func transcribeSegments(audioPath: URL) async throws -> [TimestampedSegment] {
        try await ensureModel()
        await ensureVocabularyConfiguration()

        var result = try await decodeFile(audioPath)

        // Apply CTC vocabulary rescoring if configured
        if vocabularyBooster?.rescorer != nil, let timings = result.tokenTimings, !timings.isEmpty {
            result = try await applyVocabularyRescoring(
                result: result, timings: timings, audioPath: audioPath,
            )
        }

        guard let timings = result.tokenTimings, !timings.isEmpty else {
            // No per-token timestamps: emit single segment spanning full duration
            return result.text.isEmpty ? [] : [
                TimestampedSegment(start: 0, end: result.duration, text: result.text.trimmingCharacters(in: .whitespaces)),
            ]
        }

        return ParakeetTokenGrouping.groupIntoSegments(timings)
    }

    /// Live transcription entry point: transcribe a raw 16 kHz mono Float32
    /// buffer without going through disk. Returns the decoded text without
    /// timestamps — `StreamingTranscriber` only needs the string to emit a
    /// partial/final caption. Each call gets a fresh decoder state so callers
    /// can be stateless across VAD segments.
    func transcribeSamples(_ samples: [Float]) async throws -> String {
        try await ensureModel()
        let result = try await decodeSamples(samples)
        return result.text.trimmingCharacters(in: .whitespaces)
    }

    private func decodeFile(_ audioPath: URL) async throws -> ASRResult {
        #if DEBUG
            if let fileTranscriptionOverride {
                return try await fileTranscriptionOverride(audioPath)
            }
        #endif
        guard let manager = asrManager else { throw TranscriptionError.modelNotLoaded(engine: "Parakeet") }
        var decoderState = await TdtDecoderState.make(decoderLayers: manager.decoderLayerCount)
        return try await manager.transcribe(
            audioPath, decoderState: &decoderState, language: fluidLanguageHint,
        )
    }

    private func decodeSamples(_ samples: [Float]) async throws -> ASRResult {
        #if DEBUG
            if let sampleTranscriptionOverride {
                return try await sampleTranscriptionOverride(samples)
            }
        #endif
        guard let manager = asrManager else { throw TranscriptionError.modelNotLoaded(engine: "Parakeet") }
        var decoderState = await TdtDecoderState.make(decoderLayers: manager.decoderLayerCount)
        return try await manager.transcribe(
            samples, decoderState: &decoderState, language: fluidLanguageHint,
        )
    }

    /// Run CTC keyword spotting on the audio and rescore the TDT transcript.
    private func applyVocabularyRescoring(
        result: ASRResult,
        timings: [TokenTiming],
        audioPath: URL,
    ) async throws -> ASRResult {
        guard let booster = vocabularyBooster else { return result }
        // Audio is already 16kHz mono at this point (resampled by PipelineQueue)
        let (audioSamples, _) = try await AudioMixer.loadAudioAsFloat32(url: audioPath)

        let spotResult = try await booster.spotter.spotKeywordsWithLogProbs(
            audioSamples: audioSamples,
            customVocabulary: booster.context,
        )
        guard !spotResult.logProbs.isEmpty else { return result }

        let rescoreOutput = booster.rescorer.ctcTokenRescore(
            transcript: result.text,
            tokenTimings: timings,
            logProbs: spotResult.logProbs,
            frameDuration: spotResult.frameDuration,
        )

        guard rescoreOutput.wasModified else { return result }

        let detected = rescoreOutput.replacements.compactMap(\.replacementWord)
        let applied = rescoreOutput.replacements.filter(\.shouldReplace).compactMap(\.replacementWord)
        logger.info("Parakeet: vocabulary rescoring applied \(applied.count) replacement(s)")
        // RescoreOutput only provides updated text — token timings are unchanged because
        // rescoring performs word-level text substitution without altering timing boundaries.
        return ASRResult(
            text: rescoreOutput.text,
            confidence: result.confidence,
            duration: result.duration,
            processingTime: result.processingTime,
            tokenTimings: timings,
            ctcDetectedTerms: detected.isEmpty ? nil : detected,
            ctcAppliedTerms: applied.isEmpty ? nil : applied,
        )
    }

    // MARK: - Custom Vocabulary

    #if DEBUG
        func installVocabularyPreparationForTesting(
            _ prepare: @escaping ([String]) async throws -> Void,
        ) {
            vocabularyPreparationOverride = prepare
        }

        /// Replaces the whole model load, so a test can park it without
        /// downloading or compiling a model.
        func installModelLoadForTesting(_ load: @escaping @MainActor () async -> Void) {
            modelLoadOverride = load
        }

        /// Installs the final ASR decode boundary for focused lifecycle tests. It
        /// is excluded from release builds; production always uses `AsrManager`.
        func installTranscriptionForTesting(
            file: @escaping (URL) async throws -> ASRResult,
            samples: @escaping ([Float]) async throws -> ASRResult,
        ) {
            fileTranscriptionOverride = file
            sampleTranscriptionOverride = samples
        }
    #endif

    /// Ensures the exact current file revision is ready before a decode. This
    /// makes an edit to an existing file take effect on the next transcription,
    /// and avoids an unstructured background task racing the decode.
    func ensureVocabularyConfiguration() async {
        let configuration = vocabularyConfiguration(for: customVocabularyPath, bookmark: customVocabularyBookmark)
        guard handledVocabulary != configuration else { return }
        await configureVocabulary(configuration, generation: vocabularyGeneration)
    }

    private func vocabularyConfiguration(for path: String, bookmark: Data?) -> ParakeetVocabularyConfiguration {
        guard let vocabularyURL = VocabularyFileAccess.resolve(path: path, bookmark: bookmark) else {
            return ParakeetVocabularyConfiguration(path: path, bookmark: bookmark, revision: nil)
        }
        let revision = VocabularyFileAccess.withAccess(to: vocabularyURL) { url in
            WhisperVocabularyPrompt.fileRevision(at: url.path)
        }
        return ParakeetVocabularyConfiguration(path: path, bookmark: bookmark, revision: revision)
    }

    private func configureVocabulary(_ configuration: ParakeetVocabularyConfiguration, generation: Int) async {
        guard canAdopt(configuration, generation: generation) else { return }
        // A new revision must never rescore with the prior revision while CTC
        // models are written or loaded. Mark it handled so concurrent decodes
        // do not duplicate the same preparation work.
        vocabularyBooster = nil
        handledVocabulary = configuration

        guard !configuration.path.isEmpty else { return }
        guard let terms = vocabularyTerms(for: configuration), !terms.isEmpty else {
            logger.warning("Parakeet: vocabulary file is unavailable or contains no usable terms")
            return
        }

        do {
            let booster = try await prepareBooster(terms)
            guard canAdopt(configuration, generation: generation) else { return }
            vocabularyBooster = booster
            if let booster { logger.info("Parakeet: custom vocabulary loaded: \(booster.context.terms.count) terms") }
        } catch {
            guard canAdopt(configuration, generation: generation) else { return }
            logger.warning("Parakeet: vocabulary preparation failed for \(configuration.path): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The CTC booster for `terms`. Nil under a test override, which prepares
    /// nothing real.
    private func prepareBooster(_ terms: [String]) async throws -> VocabularyBooster? {
        #if DEBUG
            if let vocabularyPreparationOverride {
                try await vocabularyPreparationOverride(terms)
                return nil
            }
        #endif
        // FluidAudio loads from a path. Give it the bounded, deduplicated list
        // shared with WhisperKit rather than the original raw file, so both
        // engines honour the validation limits users see in Settings.
        let preparedVocabularyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("parakeet-vocabulary-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: preparedVocabularyURL) }
        try terms.joined(separator: "\n").write(to: preparedVocabularyURL, atomically: true, encoding: .utf8)
        let (vocab, ctcModels) = try await CustomVocabularyContext.loadWithCtcTokens(
            from: preparedVocabularyURL.path,
            ctcVariant: .ctc110m,
        )
        let spotter = CtcKeywordSpotter(models: ctcModels, blankId: ctcModels.vocabulary.count)
        let rescorer = try await VocabularyRescorer.create(
            spotter: spotter,
            vocabulary: vocab,
            config: .default,
            ctcModelDirectory: CtcModels.defaultCacheDirectory(for: ctcModels.variant),
        )
        return VocabularyBooster(context: vocab, spotter: spotter, rescorer: rescorer)
    }

    // swiftlint:disable:next discouraged_optional_collection
    private func vocabularyTerms(for configuration: ParakeetVocabularyConfiguration) -> [String]? {
        guard let vocabularyURL = VocabularyFileAccess.resolve(
            path: configuration.path, bookmark: configuration.bookmark,
        ) else { return nil }
        // swiftlint:disable:next discouraged_optional_collection
        return VocabularyFileAccess.withAccess(to: vocabularyURL) { url -> [String]? in
            guard let revision = WhisperVocabularyPrompt.fileRevision(at: url.path),
                  case let .terms(terms) = WhisperVocabularyPrompt.read(fileAt: url.path, revision: revision)
            else { return nil }
            return terms
        }
    }

    /// Whether a preparation started under `generation` for `configuration`
    /// may still take effect: nothing changed the selection meanwhile.
    private func canAdopt(_ configuration: ParakeetVocabularyConfiguration, generation: Int) -> Bool {
        generation == vocabularyGeneration
            && configuration == vocabularyConfiguration(for: customVocabularyPath, bookmark: customVocabularyBookmark)
    }
}
