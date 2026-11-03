import AppKit
import SwiftUI

/// Settings for the model server engine: where the server is, which model to
/// ask for, and the optional command that starts it.
struct ModelServerSettingsFields: View {
    @Bindable var settings: AppSettings

    var body: some View {
        TextField("Server address", text: $settings.modelServerURL, prompt: Text("http://127.0.0.1:8000/v1"))
        HStack {
            TextField("Model", text: $settings.modelServerModel, prompt: Text("Hugging Face id or model folder"))
            Button("Choose\u{2026}", action: chooseModelFolder)
        }
        TextField(
            "Launch command",
            text: $settings.modelServerLaunchCommand,
            prompt: Text("Optional command that starts the server"),
            axis: .vertical,
        )
        .settingsNote(Self.helpText)
    }

    private func chooseModelFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.modelServerModel = url.path
        }
    }

    static let helpText = "Any server with an OpenAI-compatible /audio/transcriptions endpoint works: "
        + "an MLX server on this Mac, or vLLM on a GPU machine for models like Nemotron 3.5 Transcribe. "
        + "With a launch command, Load model starts the server when nothing answers at the address; "
        + "{model} is replaced by the model above. Speakers are still identified on this Mac."
}
