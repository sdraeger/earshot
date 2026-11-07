import SwiftUI

/// The menu-bar menu: what the app is doing, the few actions that start or
/// stop it, and the meetings it is working on. A native menu
/// (`.menuBarExtraStyle(.menu)`), read when it opens.
struct MenuBarView: View {
    let status: TranscriberStatus?
    let isWatching: Bool
    let pipelineQueue: PipelineQueue
    var updateChecker: UpdateChecker?
    let onStartStop: () -> Void
    let onRecordApp: () -> Void
    let onRecordMicrophone: () -> Void
    /// Whether the user set "No Microphone (app audio only)". Only reaches the
    /// microphone item, which it disables with a reason.
    let noMic: Bool
    /// The *wide* predicate: a manual recording that is running, or a start that
    /// has registered and not yet built its loop. `state == .recording` misses
    /// that second window, and the microphone item would sit enabled through it
    /// handing back a dead click, which is what `AppPickerStartState` was built
    /// to avoid on the picker.
    let manualRecordingPendingOrActive: Bool
    let onStopManualRecording: (() -> Void)?
    let onOpenProtocol: (JobOpenTarget) -> Void
    let onOpenProtocolsFolder: () -> Void
    let onOpenSettings: () -> Void
    /// Opens the naming window, on the given job or, for nil, the first one
    /// waiting. The row offering it shows while any job waits for names.
    let onNameSpeakers: (UUID?) -> Void
    let onProcessFiles: () -> Void
    let onQuit: () -> Void
    /// The browser whose recording-consent prompt is open, nil when none is.
    /// Mirrors the notification in the panel so a prompt hidden by Focus, screen
    /// sharing or a notification style of None can still be answered (issue #814).
    var pendingConsentApp: String?
    /// Answers the open prompt: true records, false declines.
    var onAnswerPendingConsent: (Bool) -> Void = { _ in }
    /// Whether Notion export is on. A job that has a page URL but was exported
    /// before the setting was turned off still falls back to it when no local
    /// file exists; `JobOpenTarget` owns that rule.
    var notionExportEnabled: Bool = false

    private var state: TranscriberState {
        status?.state ?? .idle
    }

    private var microphoneAvailability: MicrophoneRecordingAvailability {
        .resolve(
            isRecording: manualRecordingPendingOrActive || state == .recording,
            noMic: noMic,
        )
    }

    // Sections are separate properties so each is type-checked on its own
    // budget (the analyze build fails a getter over 300 ms).
    var body: some View {
        statusItems
        consentItems
        Divider()
        actions
        processingQueue
        updateItem
        Divider()
        Button("Open Notes Folder", action: onOpenProtocolsFolder)
        Button("Settings…", action: onOpenSettings)
            .keyboardShortcut(",")
        Divider()
        Button("Quit Earshot", action: onQuit)
            .keyboardShortcut("q")
    }

    // MARK: - Body sections

    /// What the app is doing, as disabled lines at the top of the menu.
    @ViewBuilder private var statusItems: some View {
        Text(state.label)
        if let meeting = status?.meeting {
            Text("\(meeting.title) · \(meeting.app)")
        }
        if let error = status?.error, state == .error {
            Text(error)
        }
        if let onStopManualRecording {
            Button("Stop Recording", action: onStopManualRecording)
                .keyboardShortcut(".")
        }
    }

    @ViewBuilder private var consentItems: some View {
        if let app = pendingConsentApp {
            Divider()
            Text("Record the meeting in \(app)?")
            Button("Record") { onAnswerPendingConsent(true) }
                .accessibilityIdentifier(A11yID.menuRecordPendingConsent)
            Button("Don't record") { onAnswerPendingConsent(false) }
                .accessibilityIdentifier(A11yID.menuDeclinePendingConsent)
        }
    }

    @ViewBuilder private var actions: some View {
        Toggle("Watch for Meetings", isOn: Binding(get: { isWatching }, set: { _ in onStartStop() }))
            .keyboardShortcut("s")

        if !pipelineQueue.pendingSpeakerNamingJobs.isEmpty {
            Button("Name speakers…") { onNameSpeakers(nil) }
                .keyboardShortcut("n")
        }

        if onStopManualRecording == nil, state != .recording {
            Button("Record microphone", action: onRecordMicrophone)
                .keyboardShortcut("m")
                .disabled(!microphoneAvailability.allowsStart)
            Button("Record an app…", action: onRecordApp)
                .keyboardShortcut("r")
        }

        Button("Transcribe files…", action: onProcessFiles)
            .keyboardShortcut("p")

        if let target = JobOpenTarget.resolve(for: pipelineQueue.completedJobs.last, preferNotion: notionExportEnabled) {
            Button(target.lastProtocolLabel) { onOpenProtocol(target) }
                .keyboardShortcut("o")
        }
    }

    private var queueHeader: QueueHeader {
        QueueHeader.compute(jobStates: pipelineQueue.jobs.map(\.state), isProcessing: pipelineQueue.isProcessing)
    }

    /// One submenu per job, titled with its meeting and state, holding what
    /// can be done with it.
    @ViewBuilder private var processingQueue: some View {
        if !pipelineQueue.jobs.isEmpty {
            Divider()
            Section(queueHeader.title) {
                ForEach(Array(pipelineQueue.jobs.enumerated()), id: \.element.id) { index, job in
                    Menu("\(job.meetingTitle) — \(jobStateText(job))") {
                        jobActions(job, index: index)
                    }
                }
            }
        }
    }

    @ViewBuilder private var updateItem: some View {
        if let updateChecker, let update = updateChecker.availableUpdate {
            let route = updateChecker.installRoute(for: update)
            let copiesCommand: Bool = if case .homebrew = route { true } else { false }
            Divider()
            // The menu closes on click, so say up front when this copies a
            // command rather than opening a download.
            Button(Self.updateTitle(tag: update.tagName, copiesCommand: copiesCommand)) { route.perform() }
        }
    }

    static func updateTitle(tag: String, copiesCommand: Bool) -> String {
        copiesCommand ? "Update to \(tag) (copies the brew command)" : "Update to \(tag)"
    }

    // MARK: - Jobs

    @ViewBuilder
    private func jobActions(_ job: PipelineJob, index: Int) -> some View {
        if job.state == .done, let openTarget = JobOpenTarget.resolve(for: job, preferNotion: notionExportEnabled) {
            Button(openTarget.jobActionLabel) { onOpenProtocol(openTarget) }
        }
        if job.state == .speakerNamingPending {
            Button("Name speakers…") { onNameSpeakers(job.id) }
        }
        if pipelineQueue.canRetryJob(id: job.id) {
            Button("Retry") { pipelineQueue.retryJob(id: job.id) }
                .accessibilityIdentifier(A11yID.jobRetryButton(index))
        }
        if job.state == .done, job.hasPendingNotionExport {
            Button(notionExportEnabled ? "Retry Notion export" : "Retry Notion export (turn it on in Settings → Output)") {
                Task { await pipelineQueue.retryNotionExport(id: job.id) }
            }
            .accessibilityIdentifier(A11yID.jobNotionRetryButton(index))
            .disabled(!notionExportEnabled || !job.hasRetryableNotionBackup)
        }
        if [.waiting, .transcribing, .diarizing, .generatingProtocol].contains(job.state) {
            Button("Cancel") { pipelineQueue.cancelJob(id: job.id) }
        } else if [.done, .error, .speakerNamingPending].contains(job.state) {
            Button(job.notionExportStatus == .failed ? "Discard Notion retry" : "Dismiss") {
                pipelineQueue.removeJob(id: job.id)
            }
            .disabled(job.notionExportStatus == .inProgress)
        }
    }

    private func jobStateText(_ job: PipelineJob) -> String {
        if StageKind(jobState: job.state) != nil { return Self.progressText(job: job, queue: pipelineQueue) }
        if job.state == .error, let message = job.error { return message }
        if job.state == .done, job.notionExportStatus == .inProgress { return "Exporting to Notion…" }
        if job.state == .done, !job.warnings.isEmpty { return job.warnings.joined(separator: "; ") }
        return job.state.label
    }

    /// "Transcribing… 0:42 · usually 1:10" for a job in a timed stage.
    static func progressText(job: PipelineJob, queue: PipelineQueue) -> String {
        let elapsed = queue.elapsedSeconds(forJobID: job.id)
        let base = "\(job.state.label) \(formattedTime(elapsed))"
        guard let stage = StageKind(jobState: job.state),
              let avg = queue.averageSeconds(forJobID: job.id, stage: stage), avg > 0 else { return base }
        let suffix = StageTimingStats.isSlowerThanUsual(elapsed: elapsed, average: avg)
            ? " · longer than usual (\(formattedTime(avg)))"
            : " · usually \(formattedTime(avg))"
        return base + suffix
    }
}
