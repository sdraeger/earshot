import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Pure derivations used by `OutputSettingsView`. Extracted so the wrapping
/// logic can be unit-tested without instantiating a SwiftUI host.
enum OutputSettingsLogic {
    /// Abbreviate `url` for display by replacing the home-directory prefix
    /// with `~` so paths inside the user's home stay compact. Falls back to
    /// the full path when `url` is outside `home`. Matches at the path-
    /// component boundary so `home="/Users/alice"` doesn't abbreviate
    /// `/Users/alicebob/...` to `~bob/...`.
    static func displayPath(for url: URL, home: URL) -> String {
        let path = url.path
        let homePath = home.path
        if path == homePath { return "~" }
        let prefixed = homePath.hasSuffix("/") ? homePath : homePath + "/"
        guard path.hasPrefix(prefixed) else { return path }
        return "~/" + path.dropFirst(prefixed.count)
    }

    /// Merge the currently-selected value into a picker list so the user's
    /// choice survives even when the list doesn't contain it: a model that
    /// `/models` doesn't echo back (custom Ollama tags, in-flight rename,
    /// offline cache), or a protocol language stored by an older build or set
    /// outside the app. Returns `available` unchanged when `selected` is empty
    /// or already present.
    static func mergePickerOptions(available: [String], selected: String) -> [String] {
        guard !selected.isEmpty, !available.contains(selected) else { return available }
        return [selected] + available
    }
}

enum ConnectionTestResult {
    case success(String)
    case failure(String)
}

struct OutputSettingsView: View {
    @Bindable var settings: AppSettings

    #if !APPSTORE
        @State private var claudeBinaries: [String] = ["claude"]
    #endif
    @State private var testingConnection = false
    @State private var connectionTestResult: ConnectionTestResult?
    @State private var availableModels: [String] = []
    @State private var didAttemptConnectionTest = false
    @State private var showResetPromptConfirmation = false
    @State private var hasCustomPrompt = false
    var body: some View {
        // swiftlint:disable:next closure_body_length
        Form {
            // Output folder applies to record-only AND protocol mode, so this
            // section deliberately sits outside the .recordOnlyDisabled block.
            Section("Output folder") {
                HStack {
                    Text("Output folder")
                    Spacer()
                    Text(outputDirDisplay)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack {
                    Button("Choose\u{2026}") {
                        chooseOutputFolder()
                    }

                    Button("Reset") {
                        settings.clearCustomOutputDir()
                    }
                    .disabled(settings.customOutputDirBookmark == nil)

                    Spacer()
                }
            }
            .accessibilityIdentifier(A11yID.outputFolderSection)

            NotionExportSettingsView(settings: settings)

            Section("Meeting notes") {
                Toggle("Include full transcript in meeting notes", isOn: $settings.includeFullTranscriptInProtocol)
                    .accessibilityIdentifier(A11yID.includeFullTranscriptToggle)
                Toggle("Save raw transcript separately", isOn: $settings.saveRawTranscriptSeparately)
                    .accessibilityIdentifier(A11yID.saveRawTranscriptToggle)
                Toggle("Use AI meeting title for filenames", isOn: $settings.useAITitleForFilenames)
                    .accessibilityIdentifier(A11yID.useAITitleForFilenamesToggle)

                Picker("LLM Provider", selection: $settings.protocolProvider) {
                    ForEach(ProtocolProvider.allCases, id: \.self) { provider in
                        Text(provider.label).tag(provider)
                    }
                }

                providerConfigView

                Picker("Notes language", selection: $settings.protocolLanguage) {
                    ForEach(languagePickerOptions, id: \.self) { lang in
                        Text(lang).tag(lang)
                    }
                }

                promptControls
            }
            .accessibilityIdentifier(A11yID.protocolSection)
            .recordOnlyDisabled(settings.recordOnly)
        }
        .formStyle(.grouped)
        .onAppear {
            #if !APPSTORE
                claudeBinaries = ClaudeCLIProtocolGenerator.availableClaudeBinaries()
            #endif
            refreshCustomPromptState()
        }
    }

    @ViewBuilder
    private var providerConfigView: some View { // swiftlint:disable:this attributes
        switch settings.protocolProvider {
        #if !APPSTORE
            case .claudeCLI:
                Picker("Claude CLI", selection: $settings.claudeBin) {
                    ForEach(claudeBinaries, id: \.self) { bin in
                        Text(bin).tag(bin)
                    }
                }
                .settingsNote("Binary used to generate meeting notes")

                HStack {
                    Text("API Key")
                    Spacer()
                    SecureField("", text: $settings.claudeAPIKey)
                        .frame(width: 200)
                }
                .settingsNote(
                    "Optional. Leave empty to use your \"claude login\" session.",
                    "Only set this if that session can't stay signed in. An explicit key here is billed separately from your subscription.",
                )
        #endif

        case .openAICompatible:
            openAIConfigView

        case .none:
            Text("No LLM summarization will be generated. Raw transcripts are retained if no meeting notes are saved.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var openAIConfigView: some View { // swiftlint:disable:this attributes
        VStack(alignment: .leading, spacing: 4) {
            Text("Endpoint")
            TextField("http://localhost:1234/v1", text: $settings.openAIEndpoint)
                .textFieldStyle(.roundedBorder)
            Text("Base URL (e.g. http://localhost:1234/v1) or full chat-completions URL — both work.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }

        if !availableModels.isEmpty {
            Picker("Model", selection: $settings.openAIModel) {
                ForEach(modelPickerOptions, id: \.self) { model in
                    Text(model).tag(model)
                }
            }
        } else {
            HStack {
                Text("Model")
                Spacer()
                TextField("", text: $settings.openAIModel)
                    .frame(width: 200)
                    .multilineTextAlignment(.trailing)
            }
        }

        SamplingOverrideRow(
            parameter: .temperature,
            value: $settings.openAITemperature,
            toggleID: A11yID.openAITemperatureToggle,
            valueID: A11yID.openAITemperatureValue,
        )
        SamplingOverrideRow(
            parameter: .topP,
            value: $settings.openAITopP,
            toggleID: A11yID.openAITopPToggle,
            valueID: A11yID.openAITopPValue,
        )
        .settingsNote(
            "Passed to the server only when switched on. Off leaves the server's own default in place.",
            "Some servers reject both together, and reasoning models often reject any value.",
        )

        HStack {
            Text("API Key")
            Spacer()
            SecureField("", text: $settings.openAIAPIKey)
                .frame(width: 200)
        }
        .settingsNote("Leave empty if your local server doesn't require authentication")

        Picker("API Key Authentication", selection: $settings.openAIAPIKeyPlacement) {
            ForEach(OpenAIAPIKeyPlacement.allCases, id: \.self) { placement in
                Text(placement.label).tag(placement)
            }
        }
        .accessibilityIdentifier(A11yID.openAIAPIKeyPlacementPicker)

        if settings.openAIAPIKeyPlacement == .customHeader {
            HStack {
                Text("Header name")
                Spacer()
                TextField("", text: $settings.openAIAPIKeyHeaderName)
                    .frame(width: 200)
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier(A11yID.openAIAPIKeyHeaderNameField)
            }
            .settingsNote("Sends the API key unchanged in this HTTP header, e.g. api-key.")
            if !OpenAIProtocolGenerator.isValidAPIKeyHeaderName(
                settings.openAIAPIKeyHeaderName.trimmingCharacters(in: .whitespacesAndNewlines),
            ) {
                Text("Enter a valid HTTP header name. Content-Type, Content-Length, Host and other connection-level headers are reserved.")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier(A11yID.openAIAPIKeyHeaderNameWarning)
            }
        }

        HStack {
            Button {
                testConnection()
            } label: {
                HStack(spacing: 4) {
                    if testingConnection {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(availableModels.isEmpty ? "Fetch Models" : "Refresh Models")
                }
            }
            .disabled(testingConnection)

            if let result = connectionTestResult {
                switch result {
                case let .success(msg):
                    Label(msg, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.callout)

                case let .failure(msg):
                    Label(msg, systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
        }
        .onAppear {
            if availableModels.isEmpty && !didAttemptConnectionTest {
                testConnection()
            }
        }
    }

    private var promptControls: some View {
        // swiftlint:disable:next closure_body_length
        HStack {
            Button("Edit prompt") {
                openCustomPrompt()
                refreshCustomPromptState()
            }

            Button("Import prompt") {
                importCustomPrompt()
                refreshCustomPromptState()
            }

            Button("Reset to defaults") {
                showResetPromptConfirmation = true
            }
            .disabled(!hasCustomPrompt)
            .confirmationDialog(
                "Reset meeting notes prompt to the built-in default?",
                isPresented: $showResetPromptConfirmation,
                titleVisibility: .visible,
            ) {
                Button("Reset", role: .destructive) {
                    try? FileManager.default.removeItem(at: AppPaths.customPromptFile)
                    refreshCustomPromptState()
                }
            }

            Spacer()

            if hasCustomPrompt {
                Label("Custom prompt active", systemImage: "doc.text.fill")
                    .foregroundStyle(.blue)
                    .font(.callout)
            } else {
                Label("Using default prompt", systemImage: "doc.text")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
    }

    // MARK: - Helpers

    private func refreshCustomPromptState() {
        hasCustomPrompt = FileManager.default.fileExists(atPath: AppPaths.customPromptFile.path)
    }

    func testConnection() {
        testingConnection = true
        didAttemptConnectionTest = true
        connectionTestResult = nil
        Task {
            let apiKey = settings.openAIAPIKey.isEmpty ? nil : settings.openAIAPIKey
            let result = await OpenAIProtocolGenerator.testConnection(
                endpoint: settings.openAIEndpoint,
                model: settings.openAIModel,
                apiKey: apiKey,
                apiKeyPlacement: settings.openAIAPIKeyPlacement,
                apiKeyHeaderName: settings.openAIAPIKeyHeaderName,
            )
            testingConnection = false
            switch result {
            case let .success(models):
                availableModels = models
                if !models.isEmpty {
                    // Fill in a model only when none is set: a configured name the
                    // server accepts but does not list (an alias) must survive a test.
                    if settings.openAIModel.isEmpty {
                        settings.openAIModel = models[0]
                    }
                    connectionTestResult = .success("Connected (\(models.count) models)")
                } else {
                    connectionTestResult = .success("Connected")
                }

            case let .failure(error):
                availableModels = []
                connectionTestResult = .failure(error.localizedDescription)
            }
        }
    }

    private var languagePickerOptions: [String] {
        OutputSettingsLogic.mergePickerOptions(available: AppSettings.protocolLanguages, selected: settings.protocolLanguage)
    }

    private var modelPickerOptions: [String] {
        OutputSettingsLogic.mergePickerOptions(available: availableModels, selected: settings.openAIModel)
    }

    private func ensurePromptDirectory() {
        try? FileManager.default.createDirectory(
            at: AppPaths.customPromptFile.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
    }

    private func openCustomPrompt() {
        let url = AppPaths.customPromptFile
        if !FileManager.default.fileExists(atPath: url.path) {
            ensurePromptDirectory()
            try? ProtocolGenerator.protocolPrompt.write(to: url, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(url)
    }

    private func importCustomPrompt() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .init(filenameExtension: "md")].compactMap(\.self)
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a prompt file to import"
        guard panel.runModal() == .OK, let source = panel.url else { return }
        ensurePromptDirectory()
        let dest = AppPaths.customPromptFile
        if FileManager.default.fileExists(atPath: dest.path) {
            _ = try? FileManager.default.replaceItemAt(dest, withItemAt: source)
        } else {
            try? FileManager.default.copyItem(at: source, to: dest)
        }
    }

    private var outputDirDisplay: String {
        OutputSettingsLogic.displayPath(
            for: settings.effectiveOutputDir,
            home: FileManager.default.homeDirectoryForCurrentUser,
        )
    }

    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder for recordings, transcripts and meeting notes"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.setCustomOutputDir(url)
    }
}

/// One optional sampling override: a toggle that switches it on and, while it
/// is on, a field and stepper for the value. Switching it off clears the value,
/// so the parameter is left out of the request and the server default applies.
private struct SamplingOverrideRow: View {
    let parameter: OpenAISamplingParameter
    @Binding var value: Double?
    let toggleID: String
    let valueID: String

    var body: some View {
        Toggle("Override \(parameter.label)", isOn: isOverridden)
            .accessibilityIdentifier(toggleID)

        if value != nil {
            HStack {
                Text(parameter.label)
                Spacer()
                TextField(parameter.label, value: currentValue, format: .number)
                    .labelsHidden()
                    .frame(width: 60)
                    .multilineTextAlignment(.trailing)
                Stepper(parameter.label, value: currentValue, in: parameter.range, step: 0.05)
                    .labelsHidden()
            }
            // A container element, so the identifier names the row instead
            // of being copied onto the label, field and stepper inside it.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(valueID)
        }
    }

    private var isOverridden: Binding<Bool> {
        Binding(
            get: { value != nil },
            set: { value = $0 ? OpenAISamplingParameter.initialOverride : nil },
        )
    }

    private var currentValue: Binding<Double> {
        Binding(
            // The row only renders while overridden; the fallback just makes it total.
            get: { value ?? OpenAISamplingParameter.initialOverride },
            set: { value = $0 },
        )
    }
}
