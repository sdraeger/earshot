import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Bindable var settings: AppSettings
    var whisperKitEngine: WhisperKitEngine
    var parakeetEngine: ParakeetEngine
    var modelServerEngine: ModelServerEngine = .init()
    var updateChecker: UpdateChecker?

    /// Notification visibility from `PermissionsController`, forwarded to the
    /// General tab so it can warn when browser-meeting consent cannot reach the
    /// user. Nil until the first permission check completes.
    var notificationVisibility: NotificationVisibility?
    /// Required: the same actor instance the pipeline writes to, so the Stats
    /// tab and the pipeline don't race two writers on `recognition_log.jsonl`.
    var recognitionStatsLog: RecognitionStatsLog
    /// Same actor instance the pipeline writes to, so the Processing Stats tab
    /// and the pipeline don't race two writers on `stage_timing.jsonl`.
    var stageTimingLog: StageTimingLog
    /// Factory for the voice-enrollment diarizer. nil → enroll button hidden.
    var enrollmentDiarizerFactory: (() -> any DiarizationProvider)?
    /// True when a meeting is currently waiting on a naming dialog. We gate
    /// the enroll button to avoid two `SpeakerNamingView` instances.
    var namingDialogActive: Bool = false
    /// True when the pipeline is processing a job — soft hint only.
    var pipelineBusy: Bool = false
    var onSpeakerMutate: (() -> Void)?
    /// Builds the matcher Known Voices and enrollment edit through.
    var speakerMatcherFactory: () -> SpeakerMatcher = { SpeakerMatcher() }
    /// The old-models row's state, built once by `EngineController`. Nil leaves the row
    /// out, which is what tests and the App Store build get.
    var legacyWhisperModels: LegacyWhisperModelsState?

    @State private var selection: SettingsTab = .general
    private static let maxColumn: CGFloat = 680

    var body: some View {
        splitView
    }

    private var splitView: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $selection) { tab in
                Label(tab.label, systemImage: tab.systemImage)
                    .padding(.vertical, 3)
                    .tag(tab)
                    .accessibilityIdentifier(A11yID.settingsTab(tab.rawValue))
            }
            .safeAreaInset(edge: .top, alignment: .leading) {
                Text("Earshot")
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 240)
        } detail: {
            // A centered column no wider than `maxColumn`: rows stretched across
            // a wide window put a label and its control too far apart to scan.
            // Margins rather than a max width keep the scrollbar at the edge.
            GeometryReader { proxy in
                detailView(for: selection)
                    .contentMargins(
                        .horizontal, max(28, (proxy.size.width - Self.maxColumn) / 2), for: .scrollContent,
                    )
                    .scrollContentBackground(.hidden)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        SettingsPageHeader(title: selection.label, subtitle: selection.subtitle)
                            .padding(.horizontal, max(48, (proxy.size.width - Self.maxColumn) / 2 + 20))
                    }
            }
            .background(Theme.paper)
            .navigationTitle("")
        }
        .tint(Theme.accent)
        .frame(
            minWidth: 820,
            idealWidth: 960,
            maxWidth: 1200,
            minHeight: 560,
            idealHeight: 720,
            maxHeight: .infinity,
        )
    }

    @ViewBuilder
    private func detailView(for tab: SettingsTab) -> some View {
        switch tab {
        case .general:
            GeneralSettingsView(
                settings: settings,
                notificationVisibility: notificationVisibility,
            )

        case .audio:
            AudioSettingsView(settings: settings)

        case .transcription:
            TranscriptionSettingsView(
                settings: settings,
                whisperKitEngine: whisperKitEngine,
                parakeetEngine: parakeetEngine,
                modelServerEngine: modelServerEngine,
                legacyModels: legacyWhisperModels,
            )

        case .speakers:
            SpeakersSettingsView(
                settings: settings,
                recognitionStatsLog: recognitionStatsLog,
                stageTimingLog: stageTimingLog,
                enrollmentDiarizerFactory: enrollmentDiarizerFactory,
                namingDialogActive: namingDialogActive,
                pipelineBusy: pipelineBusy,
                onSpeakerMutate: onSpeakerMutate,
                matcherFactory: speakerMatcherFactory,
            )

        case .output:
            OutputSettingsView(settings: settings)

        case .advanced:
            AdvancedSettingsView(settings: settings)

        case .about:
            AboutSettingsView(settings: settings, updateChecker: updateChecker)
        }
    }
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general, audio, transcription, speakers, output, advanced, about

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .general: "General"
        case .audio: "Audio"
        case .transcription: "Transcription"
        case .speakers: "Speakers"
        case .output: "Output"
        case .advanced: "Advanced"
        case .about: "About"
        }
    }

    /// One line under the page title saying what the page holds.
    var subtitle: String {
        switch self {
        case .general: "When Earshot records, and how it tells you."
        case .audio: "Microphone, voice detection and echo."
        case .transcription: "Speech recognition, live captions and vocabulary."
        case .speakers: "Voices Earshot knows and how it tells them apart."
        case .output: "Where your notes go and how they are written."
        case .advanced: "Permissions and diagnostics."
        case .about: "Version and updates."
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gear"
        case .audio: "mic"
        case .transcription: "waveform"
        case .speakers: "person.2"
        case .output: "doc.text"
        case .advanced: "wrench.and.screwdriver"
        case .about: "info.circle"
        }
    }
}
