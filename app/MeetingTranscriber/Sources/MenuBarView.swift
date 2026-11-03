import SwiftUI

/// The menu-bar panel: what the app is doing, the few actions that start or
/// stop it, and the meetings it is working on. Shown with
/// `.menuBarExtraStyle(.window)`, so it updates live while open.
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
    let onNameSpeakers: (() -> Void)?
    let onProcessFiles: () -> Void
    let onDismissJob: (UUID) -> Void
    let onQuit: () -> Void
    /// The browser whose recording-consent prompt is open, nil when none is.
    /// Mirrors the notification in the panel so a prompt hidden by Focus, screen
    /// sharing or a notification style of None can still be answered (issue #814).
    var pendingConsentApp: String?
    /// Answers the open prompt: true records, false declines.
    var onAnswerPendingConsent: (Bool) -> Void = { _ in }
    /// Opens the naming window on one job; falls back to `onNameSpeakers`.
    var onNameSpeakersForJob: ((UUID) -> Void)?
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
        VStack(alignment: .leading, spacing: 16) {
            statusHeader
            consentPrompt
            actions
            processingQueue
            updateSection
            footer
        }
        .padding(16)
        .frame(width: 340)
        .background(CenterUnderClick())
    }

    // MARK: - Body sections

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(state.label, systemImage: state.icon)
                .font(.headline)
                .foregroundStyle(state.tint)

            meetingInfo
            errorInfo
            stopRecordingButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var meetingInfo: some View {
        if let meeting = status?.meeting {
            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                Text(meeting.app)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var errorInfo: some View {
        if let error = status?.error, state == .error {
            Text(error)
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var stopRecordingButton: some View {
        if let onStopManualRecording {
            Button(action: onStopManualRecording) {
                Label("Stop recording", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .keyboardShortcut(".")
            .padding(.top, 4)
        }
    }

    @ViewBuilder private var consentPrompt: some View {
        if let app = pendingConsentApp {
            VStack(alignment: .leading, spacing: 10) {
                Text("Record the meeting in \(app)?")
                    .font(.headline)
                HStack {
                    Button("Don't record") { onAnswerPendingConsent(false) }
                        .accessibilityIdentifier(A11yID.menuDeclinePendingConsent)
                    Spacer()
                    Button("Record") { onAnswerPendingConsent(true) }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier(A11yID.menuRecordPendingConsent)
                }
            }
            .panelCard()
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(isOn: Binding(get: { isWatching }, set: { _ in onStartStop() })) {
                Label("Watch for meetings", systemImage: "antenna.radiowaves.left.and.right")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .keyboardShortcut("s")
            .padding(.horizontal, 8)
            .padding(.vertical, 7)

            if let onNameSpeakers {
                PanelRow("Name speakers…", systemImage: "person.2.fill", action: onNameSpeakers)
                    .foregroundStyle(.tint)
                    .keyboardShortcut("n")
            }

            if onStopManualRecording == nil, state != .recording {
                PanelRow("Record microphone", systemImage: "mic", action: onRecordMicrophone)
                    .keyboardShortcut("m")
                    .disabled(!microphoneAvailability.allowsStart)
                    .help(microphoneAvailability.disabledReason ?? "Record the microphone only, with no app audio")

                PanelRow("Record an app…", systemImage: "macwindow", action: onRecordApp)
                    .keyboardShortcut("r")
            }

            PanelRow("Transcribe files…", systemImage: "doc.badge.plus", action: onProcessFiles)
                .keyboardShortcut("p")

            lastNotesRow
        }
        .labelStyle(PanelLabelStyle())
    }

    @ViewBuilder private var lastNotesRow: some View {
        if let target = JobOpenTarget.resolve(for: pipelineQueue.completedJobs.last, preferNotion: notionExportEnabled) {
            PanelRow(target.lastProtocolLabel, systemImage: target.systemImage) { onOpenProtocol(target) }
                .keyboardShortcut("o")
        }
    }

    private var queueHeader: QueueHeader {
        QueueHeader.compute(jobStates: pipelineQueue.jobs.map(\.state), isProcessing: pipelineQueue.isProcessing)
    }

    @ViewBuilder private var processingQueue: some View {
        if !pipelineQueue.jobs.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(queueHeader.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                ForEach(Array(pipelineQueue.jobs.enumerated()), id: \.element.id) { index, job in
                    jobRow(job, index: index)
                }
            }
        }
    }

    @ViewBuilder private var updateSection: some View {
        if let updateChecker, let update = updateChecker.availableUpdate {
            let route = updateChecker.installRoute(for: update)
            Button {
                route.perform()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Update to \(update.tagName)", systemImage: "arrow.down.circle.fill")
                    if case .homebrew = route {
                        // The panel closes on click, so say up front that this
                        // copies a command rather than opening a download.
                        Text("Copies the brew upgrade command")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .panelCard()
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Button(action: onOpenProtocolsFolder) {
                Label("Notes folder", systemImage: "folder")
            }
            Spacer()
            Button(action: onOpenSettings) {
                Label("Settings…", systemImage: "gear")
            }
            .keyboardShortcut(",")
            Button("Quit", action: onQuit)
                .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .labelStyle(PanelLabelStyle())
        .padding(.horizontal, 8)
    }

    // MARK: - Jobs

    private func jobRow(_ job: PipelineJob, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(job.meetingTitle)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                dismissOrCancelButton(job)
            }
            jobStateLabel(job)
            jobActions(job, index: index)
        }
        .panelCard()
    }

    @ViewBuilder
    private func jobActions(_ job: PipelineJob, index: Int) -> some View {
        let openTarget = job.state == .done
            ? JobOpenTarget.resolve(for: job, preferNotion: notionExportEnabled) : nil
        let showRetry = pipelineQueue.canRetryJob(id: job.id)
        let showNotionRetry = job.state == .done && job.hasPendingNotionExport
        if openTarget != nil || job.state == .speakerNamingPending || showRetry || showNotionRetry {
            HStack(spacing: 8) {
                if let openTarget {
                    Button(openTarget.jobActionLabel) { onOpenProtocol(openTarget) }
                }
                if job.state == .speakerNamingPending {
                    Button("Name speakers…") {
                        if let onNameSpeakersForJob { onNameSpeakersForJob(job.id) } else { onNameSpeakers?() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                if showRetry {
                    Button("Retry") { pipelineQueue.retryJob(id: job.id) }
                        .accessibilityIdentifier(A11yID.jobRetryButton(index))
                }
                if showNotionRetry {
                    Button("Retry Notion export") {
                        Task { await pipelineQueue.retryNotionExport(id: job.id) }
                    }
                    .accessibilityIdentifier(A11yID.jobNotionRetryButton(index))
                    .disabled(!notionExportEnabled || !job.hasRetryableNotionBackup)
                    .help(notionExportEnabled ? "" : "Turn on Notion export in Settings → Output to retry.")
                }
            }
            .controlSize(.small)
        }
    }

    /// One trailing control per job: Cancel while it runs, Dismiss once it has
    /// settled.
    @ViewBuilder
    private func dismissOrCancelButton(_ job: PipelineJob) -> some View {
        if [.waiting, .transcribing, .diarizing, .generatingProtocol].contains(job.state) {
            iconButton("Cancel", systemImage: "xmark.circle.fill") { pipelineQueue.cancelJob(id: job.id) }
        } else if [.done, .error, .speakerNamingPending].contains(job.state) {
            iconButton(
                job.notionExportStatus == .failed ? "Discard Notion retry" : "Dismiss",
                systemImage: "xmark",
            ) { onDismissJob(job.id) }
                .disabled(job.notionExportStatus == .inProgress)
        }
    }

    private func iconButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage).labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(title)
    }

    private func jobStateLabel(_ job: PipelineJob) -> some View {
        Group {
            if StageKind(jobState: job.state) != nil {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(Self.progressText(job: job, queue: pipelineQueue))
                }
            } else if job.state == .error, let msg = job.error {
                Text(msg).foregroundStyle(.red)
            } else if job.state == .done, job.notionExportStatus == .inProgress {
                Text("Exporting to Notion…")
            } else if job.state == .done, !job.warnings.isEmpty {
                Text(job.warnings.joined(separator: "; "))
            } else {
                Text(job.state.label)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
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

// MARK: - Panel building blocks

/// Icons in a fixed-width column so the row titles share one left edge.
private struct PanelLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .frame(width: 18)
            configuration.title
        }
    }
}

/// A full-width action row that highlights under the pointer, like a menu item.
private struct PanelRow: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    init(_ title: String, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PanelRowStyle())
    }
}

private struct PanelRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Highlight(configuration: configuration)
    }

    private struct Highlight: View {
        let configuration: Configuration
        @Environment(\.isEnabled)
        private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(fillOpacity)),
                )
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { hovering = $0 }
        }

        private var fillOpacity: Double {
            guard isEnabled else { return 0 }
            if configuration.isPressed { return 0.14 }
            return hovering ? 0.08 : 0
        }
    }
}

/// SwiftUI placed the `.window` panel about 235 pt right of the menu-bar icon
/// (measured on macOS 26 with the icon on a second display), so each time the
/// panel shows, this centers it under the click that opened it.
private struct CenterUnderClick: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        Anchor()
    }

    func updateNSView(_: NSView, context _: Context) {}

    final class Anchor: NSView {
        private var observers: [any NSObjectProtocol] = []
        /// The click's x, kept so a resize (a job appearing) re-centers on the
        /// same point after the pointer has moved on.
        private var clickX: CGFloat?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            let center = NotificationCenter.default
            observers = [
                center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.place(atClick: true) }
                },
                center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.place(atClick: false) }
                },
            ]
        }

        private func place(atClick: Bool) {
            guard let window else { return }
            let mouse = NSEvent.mouseLocation
            // Only a click in the menu bar, above the panel, says where the icon is.
            if atClick, mouse.y >= window.frame.maxY { clickX = mouse.x }
            guard let clickX,
                  let visible = (NSScreen.screens.first { $0.frame.contains(mouse) } ?? window.screen)?.visibleFrame
            else { return }
            let width = window.frame.width
            let x = min(max(clickX - width / 2, visible.minX + 8), visible.maxX - width - 8)
            if abs(window.frame.minX - x) > 0.5 {
                window.setFrameOrigin(NSPoint(x: x, y: window.frame.minY))
            }
        }
    }
}

private extension View {
    /// A block set off from the panel by a step in tone, with no outline.
    func panelCard() -> some View {
        padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

private extension TranscriberState {
    var tint: Color {
        switch self {
        case .recording, .error: .red
        default: .primary
        }
    }
}
