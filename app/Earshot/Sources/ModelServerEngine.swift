import Foundation
import Observation

/// Transcribes through any server that speaks the OpenAI audio API
/// (`POST {baseURL}/audio/transcriptions`): an MLX server on this Mac, or vLLM
/// on a GPU machine elsewhere. Diarization stays on-device, so the server only
/// has to return text with segment timestamps.
///
/// When `launchCommand` is set and nothing answers at `baseURL`, `loadModel()`
/// starts the server itself (`{model}` in the command becomes `model`) and
/// waits for it, so a model folder or Hugging Face id is all the user supplies.
@Observable
@MainActor
final class ModelServerEngine: TranscribingEngine {
    private(set) var modelState: EngineModelState = .unloaded
    let downloadProgress: Double = 0
    /// Why the last load or transcription failed, shown under the engine status.
    private(set) var loadFailureReason: String?
    /// False after a response without segments: one block of text cannot be
    /// diarized, and the pipeline then skips diarization with a warning.
    private(set) var providesTimestamps = true

    /// e.g. `http://127.0.0.1:8000/v1`
    var baseURL = ""
    /// Sent as the request's `model`; a Hugging Face id or a local path.
    var model = ""
    /// Shell command that starts the server; empty means connect only.
    var launchCommand = ""

    /// The launched shell; it leads its own process group, which holds the server.
    @ObservationIgnored private var serverPID: pid_t?
    @ObservationIgnored private var serverLog: URL?
    @ObservationIgnored private let session: URLSession
    /// How long a launched server may take to answer: a first run downloads the model.
    static let startupTimeout: Duration = .seconds(600)

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Loading

    func loadModel() async {
        loadFailureReason = nil
        guard let base = URL(string: baseURL), base.scheme != nil else {
            fail("Enter the server address, for example http://127.0.0.1:8000/v1.")
            return
        }
        modelState = .loading
        if await isReachable(base) {
            modelState = .loaded
            return
        }
        let command = launchCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            fail("No server answers at \(baseURL). Start one, or add a launch command.")
            return
        }
        do {
            try startServer(command.replacingOccurrences(of: "{model}", with: model))
        } catch {
            fail("Could not run the launch command: \(error.localizedDescription)")
            return
        }
        let deadline = ContinuousClock.now + Self.startupTimeout
        while ContinuousClock.now < deadline {
            if await isReachable(base) {
                modelState = .loaded
                return
            }
            if let status = exitStatusIfExited() {
                fail("The server exited with status \(status). \(logTail())")
                return
            }
            try? await Task.sleep(for: .seconds(1))
        }
        fail("The server did not answer at \(baseURL) within 10 minutes. \(logTail())")
    }

    private func fail(_ reason: String) {
        loadFailureReason = reason
        modelState = .unloaded
    }

    /// Any HTTP answer counts: not every server implements `/models`.
    private func isReachable(_ base: URL) async -> Bool {
        var request = URLRequest(url: base.appendingPathComponent("models"))
        request.timeoutInterval = 3
        return await (try? session.data(for: request).1) is HTTPURLResponse
    }

    /// Runs through a login shell so tools on the user's PATH (Homebrew, uv,
    /// pipx) resolve. The shell is spawned as the leader of a new process
    /// group, so stopping signals the group and takes down whatever the command
    /// started (a `uvx` wrapper and its Python server) along with the shell.
    private func startServer(_ command: String) throws {
        stopServer()
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("model-server.log")
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attributes, 0)
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 1, log.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        posix_spawn_file_actions_adddup2(&actions, 1, 2)

        let argv: [UnsafeMutablePointer<CChar>?] = ["/bin/zsh", "-lc", command].map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var pid: pid_t = 0
        let result = posix_spawn(&pid, "/bin/zsh", &actions, &attributes, argv, environ)
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: result) ?? .EINVAL) }
        serverPID = pid
        serverLog = log
    }

    /// The shell's exit status once it has exited (reaping it), nil while it runs.
    private func exitStatusIfExited() -> Int32? {
        guard let pid = serverPID else { return nil }
        var status: Int32 = 0
        guard waitpid(pid, &status, WNOHANG) == pid else { return nil }
        serverPID = nil
        return (status >> 8) & 0xFF
    }

    func stopServer() {
        guard let pid = serverPID else { return }
        kill(-pid, SIGTERM)
        var status: Int32 = 0
        waitpid(pid, &status, 0)
        serverPID = nil
    }

    private func logTail() -> String {
        guard let serverLog, let text = try? String(contentsOf: serverLog, encoding: .utf8) else { return "" }
        let tail = text.split(separator: "\n").suffix(3).joined(separator: " ")
        return tail.isEmpty ? "" : "Last output: \(tail)"
    }

    // MARK: - Transcription

    func transcribeSegments(audioPath: URL) async throws -> [TimestampedSegment] {
        guard modelState == .loaded, let base = URL(string: baseURL) else {
            throw TranscriptionError.modelNotLoaded(reason: loadFailureReason)
        }
        let boundary = UUID().uuidString
        var request = URLRequest(url: base.appendingPathComponent("audio/transcriptions"))
        request.httpMethod = "POST"
        request.timeoutInterval = 3600 // a long meeting on a slow server
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let body = try Self.multipartBody(
            fields: ["model": model, "response_format": "verbose_json", "timestamp_granularities[]": "segment"],
            file: audioPath, boundary: boundary,
        )

        let (data, httpResponse) = try await session.upload(for: request, from: body)
        let status = (httpResponse as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let detail = String(data: data.prefix(300), encoding: .utf8) ?? ""
            throw ModelServerError.http(status: status, detail: detail)
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        providesTimestamps = response.segments?.isEmpty == false
        return response.timestampedSegments
    }

    struct Response: Decodable {
        struct Segment: Decodable {
            let start: Double
            let end: Double
            let text: String
        }

        let text: String?
        // Optional because servers omit the key when they have no timestamps.
        // swiftlint:disable:next discouraged_optional_collection
        let segments: [Segment]?
        let duration: Double?

        /// Segments when the server sends them, else the whole text as one segment.
        var timestampedSegments: [TimestampedSegment] {
            if let segments, !segments.isEmpty {
                return segments.map { segment in
                    TimestampedSegment(
                        start: segment.start, end: segment.end,
                        text: segment.text.trimmingCharacters(in: .whitespaces),
                    )
                }
            }
            guard let text, !text.isEmpty else { return [] }
            return [TimestampedSegment(start: 0, end: duration ?? 0, text: text)]
        }
    }

    static func multipartBody(fields: [String: String], file: URL, boundary: String) throws -> Data {
        var body = Data()
        func header(_ disposition: String, contentType: String = "") {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; \(disposition)\r\n\(contentType)\r\n".utf8))
        }
        for (name, value) in fields.sorted(by: { $0.key < $1.key }) where !value.isEmpty {
            header("name=\"\(name)\"")
            body.append(Data("\(value)\r\n".utf8))
        }
        header("name=\"file\"; filename=\"\(file.lastPathComponent)\"", contentType: "Content-Type: audio/wav\r\n")
        try body.append(Data(contentsOf: file))
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }
}

enum ModelServerError: LocalizedError {
    case http(status: Int, detail: String)

    var errorDescription: String? {
        switch self {
        case let .http(status, detail):
            status == 0
                ? "The model server did not answer."
                : "The model server answered \(status): \(detail)"
        }
    }
}
