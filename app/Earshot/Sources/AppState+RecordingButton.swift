import Foundation

/// What the floating recording button (`RecordingButtonPanel`) reads and does.
extension AppState {
    /// The floating recording button shows while a recording runs, unless
    /// turned off in Settings → General.
    var shouldShowRecordingButton: Bool {
        settings.recordingButtonEnabled && watching.isRecording
    }

    /// The louder of the two capture channels, in dBFS, for the button's bars.
    /// -120 when nothing records.
    var recordingLevelDBFS: Double {
        guard let recorder = watching.watchLoop?.activeRecorder else { return -120 }
        return max(recorder.micLevelDBFS, recorder.appLevelDBFS)
    }

    /// What the button's Stop item does: end a manual recording, or stop
    /// watching, which ends an auto-detected one.
    var recordingButtonStopTitle: String {
        isManualRecording ? "Stop Recording" : "Stop Recording and Watching"
    }

    func stopFromRecordingButton() {
        if isManualRecording {
            watching.stopManualRecording()
        } else if isWatching {
            watching.toggleWatching()
        }
    }
}
