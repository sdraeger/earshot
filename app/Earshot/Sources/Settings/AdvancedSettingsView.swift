import AppKit
import ApplicationServices
import AudioTapLib
import AVFoundation
import os.log
import SwiftUI

private let logger = Logger(subsystem: AppPaths.logSubsystem, category: "AdvancedSettingsView")

private enum PrivacyPane: String {
    case screenCapture = "Privacy_ScreenCapture"
    case microphone = "Privacy_Microphone"
    case accessibility = "Privacy_Accessibility"

    var url: String {
        "x-apple.systempreferences:com.apple.preference.security?\(rawValue)"
    }
}

struct AdvancedSettingsView: View {
    @Bindable var settings: AppSettings

    @State private var micPermission: AVAuthorizationStatus = .notDetermined
    @State private var screenRecordingOK = false
    @State private var accessibilityOK = false
    @State private var lastExportFile: String?
    @State private var lastExportError: String?
    /// True while a `DiagnosticExporter.export` call is running off-main.
    /// Used to dim the button and surface a spinner so a 50-200 MB persistent
    /// log doesn't look like the app froze.
    @State private var isExportingDiagnostics = false

    var body: some View {
        // swiftlint:disable:next closure_body_length
        Form {
            permissionsSection

            // swiftlint:disable:next closure_body_length
            Section("Diagnostics") {
                Toggle("Verbose diagnostic logging", isOn: $settings.verboseDiagnostics)
                    .settingsNote(
                        "Logs detailed diagnostics across recording, transcription,"
                            + " diarization, and meeting notes generation. Used to debug"
                            + " issues. Off by default — toggle on, reproduce the"
                            + " problem, then click \"Export Diagnostics…\" below to"
                            + " attach a redacted log file to a bug report.",
                    )

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Button("Export diagnostics…") { exportDiagnostics() }
                            .disabled(isExportingDiagnostics)
                        if isExportingDiagnostics {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    if let file = lastExportFile {
                        Text("Exported to: \(file)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if let err = lastExportError {
                        Text("Export failed: \(err)")
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }

                #if !APPSTORE
                    Button("Open diagnostic logs folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([PersistentDiagnosticLog.logDirectory])
                    }
                    .settingsNote(
                        "Persistent logs are kept for 30 days at"
                            + " ~/Library/Logs/Earshot/. Useful when"
                            + " you need to attach logs from a session that"
                            + " happened earlier today (or yesterday).",
                    )

                    Toggle("Local Automation API", isOn: $settings.debugRPCEnabled)
                        .settingsNote(
                            "Exposes the local automation API + pipeline state on"
                                + " 127.0.0.1:9876 (POST /v1/transcribe, /v1/jobs, and"
                                + " /v1/watch to start/stop watching from a hotkey or"
                                + " Stream Deck; also `mt-cli`). Localhost-only,"
                                + " bearer-token auth. Off by default; enable for"
                                + " headless automation or shell-driven inspection.",
                        )
                #endif
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshPermissions() }
    }

    private var permissionsSection: some View {
        // swiftlint:disable:next closure_body_length
        Section("Permissions") {
            PermissionRow(
                label: "Screen Recording",
                detail: Self.screenRecordingDetail,
                granted: screenRecordingOK,
                help: "\(SystemSettingsPaths.screenRecording) → enable Earshot",
                settingsURL: PrivacyPane.screenCapture.url,
            ) {
                // macOS cannot grant this in place; the request lists the app
                // in the pane, and the switch there takes effect after a relaunch.
                Permissions.ensureScreenRecordingAccess()
                Self.open(.screenCapture)
            }
            PermissionRow(
                label: "Microphone",
                detail: micPermission == .authorized ? "Granted"
                    : micPermission == .notDetermined ? "Will prompt on first recording"
                    : "Denied — click to open Settings",
                granted: micPermission == .authorized,
                warning: micPermission == .notDetermined,
                help: "System Settings → Privacy & Security → Microphone → enable Earshot",
                settingsURL: PrivacyPane.microphone.url,
            ) {
                // Undecided: macOS asks in place. Denied: only the pane can change it.
                if micPermission == .notDetermined {
                    Task {
                        _ = await Permissions.ensureMicrophoneAccess()
                        refreshPermissions()
                    }
                } else {
                    Self.open(.microphone)
                }
            }
            PermissionRow(
                label: "Accessibility",
                detail: "Optional — enables mute detection and meeting naming",
                granted: accessibilityOK,
                optional: true,
                help: "System Settings → Privacy & Security → Accessibility → enable Earshot",
                settingsURL: PrivacyPane.accessibility.url,
            ) {
                Permissions.ensureAccessibilityAccess()
                Self.open(.accessibility)
            }

            Button("Refresh") {
                refreshPermissions()
            }
            .font(.callout)
        }
    }

    #if APPSTORE
        private static let screenRecordingDetail = "Required for app audio capture"
    #else
        private static let screenRecordingDetail = "Required for meeting detection and app audio capture"
    #endif

    private static func open(_ pane: PrivacyPane) {
        if let url = URL(string: pane.url) { NSWorkspace.shared.open(url) }
    }

    private func refreshPermissions() {
        micPermission = AVCaptureDevice.authorizationStatus(for: .audio)
        screenRecordingOK = Permissions.checkScreenRecording()
        accessibilityOK = AXIsProcessTrusted()
    }

    private func exportDiagnostics() {
        guard !isExportingDiagnostics else { return }
        let stamp = Int(Date().timeIntervalSince1970)
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Earshot-diagnostics-\(stamp).log")
        let info = DiagnosticExporter.HeaderInfo(
            appVersion: Bundle.main.appVersion,
            commit: Bundle.main.gitCommitHash,
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            settings: [
                "verboseDiagnostics": "\(settings.verboseDiagnostics)",
                "diarize": "\(settings.diarize)",
                "vadEnabled": "\(settings.vadEnabled)",
                "transcriptionEngine": settings.transcriptionEngine.rawValue,
                "protocolProvider": settings.protocolProvider.rawValue,
                "recordOnly": "\(settings.recordOnly)",
            ],
        )

        isExportingDiagnostics = true
        // The persistent-log file source can be 50-200 MB and reads via
        // `String(contentsOf:)` + `split(separator:)` — and the OSLogStore
        // fallback's `getEntries` is famously slow on the main actor. Detach
        // so the Settings UI stays responsive while the export runs.
        Task.detached(priority: .userInitiated) {
            let result = Result { try DiagnosticExporter.export(to: outURL, info: info) }
            await MainActor.run {
                isExportingDiagnostics = false
                switch result {
                case let .success(count):
                    lastExportFile = outURL.lastPathComponent
                    lastExportError = nil
                    NSWorkspace.shared.activateFileViewerSelecting([outURL])
                    let exportedFile = outURL.lastPathComponent
                    logger.info(
                        "diagnostics_exported lines=\(count, privacy: .public) file=\(exportedFile, privacy: .public)",
                    )

                case let .failure(error):
                    lastExportFile = nil
                    lastExportError = error.localizedDescription
                    logger.error(
                        "diagnostics_export_failed error=\(error.localizedDescription, privacy: .public)",
                    )
                }
            }
        }
    }
}
