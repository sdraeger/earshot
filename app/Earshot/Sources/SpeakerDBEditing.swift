import Foundation

/// What Settings needs to edit the speaker database from Known Voices and
/// voice enrollment. One value, so the views between `AppState` and
/// `KnownVoicesView` pass it on without knowing its parts.
struct SpeakerDBEditing {
    /// The matcher every edit goes through.
    var makeMatcher: () -> SpeakerMatcher = { SpeakerMatcher() }
    /// The enrollment diarizer; nil hides the enroll button.
    var makeDiarizer: (() -> any DiarizationProvider)?
    /// A meeting waits on the naming dialog, so enrollment, which shows a
    /// second one, is disabled.
    var namingDialogActive = false
    /// The pipeline is transcribing or diarizing: a hint, not a block.
    var pipelineBusy = false
    /// Runs after any edit, so caches that mirror the database (the naming
    /// dialog's known-name chips, issue #155) are refreshed.
    var didMutate: () -> Void = {}
}

extension AppState {
    /// The pipeline's database file and the app's notifier, so Known Voices,
    /// enrollment and the automation API edit one database and report
    /// through one channel.
    var speakerDBEditing: SpeakerDBEditing {
        SpeakerDBEditing(
            makeMatcher: SpeakerMatcher.factory(dbPath: pipeline.speakersDB, notifier: notifier),
            makeDiarizer: { [settings] in FluidDiarizer(mode: settings.diarizerMode) },
            namingDialogActive: pipeline.queue.pendingSpeakerNaming != nil,
            pipelineBusy: pipeline.queue.isProcessing,
            // swiftlint:disable:next trailing_closure
            didMutate: { [weak self] in self?.pipeline.queue.refreshKnownSpeakerNames() },
        )
    }
}
