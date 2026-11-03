@testable import MeetingTranscriber
import XCTest

@MainActor
final class ModelServerEngineTests: XCTestCase {
    // MARK: - Response parsing

    func testSegmentsKeepTheirTimestamps() throws {
        let json = #"{"text":"Hi there. Bye.","segments":[{"start":0.0,"end":1.5,"text":" Hi there."},{"start":1.5,"end":2.0,"text":" Bye."}]}"#
        let segments = try JSONDecoder().decode(ModelServerEngine.Response.self, from: Data(json.utf8))
            .timestampedSegments
        XCTAssertEqual(segments.map(\.text), ["Hi there.", "Bye."])
        XCTAssertEqual(segments.map(\.end), [1.5, 2.0])
    }

    func testTextWithoutSegmentsBecomesOneSegment() throws {
        let json = #"{"text":"Whole meeting.","duration":42}"#
        let segments = try JSONDecoder().decode(ModelServerEngine.Response.self, from: Data(json.utf8))
            .timestampedSegments
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments.first?.end, 42)
    }

    func testMultipartBodyCarriesFieldsAndFile() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("mp-\(UUID().uuidString).wav")
        try Data("RIFF".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let body = try ModelServerEngine.multipartBody(fields: ["model": "m1", "empty": ""], file: file, boundary: "B")
        let text = try XCTUnwrap(String(data: body, encoding: .utf8))
        XCTAssertTrue(text.contains("name=\"model\"\r\n\r\nm1\r\n"))
        XCTAssertFalse(text.contains("name=\"empty\""), "empty fields are left out")
        XCTAssertTrue(text.contains("filename=\"\(file.lastPathComponent)\""))
        XCTAssertTrue(text.hasSuffix("RIFF\r\n--B--\r\n"))
    }

    // MARK: - Loading errors

    func testLoadWithoutAnAddressExplainsWhatToEnter() async {
        let engine = ModelServerEngine()
        await engine.loadModel()
        XCTAssertEqual(engine.modelState, .unloaded)
        XCTAssertTrue(engine.loadFailureReason?.contains("server address") == true)
    }

    func testLoadWithNothingListeningAndNoCommandSaysSo() async {
        let engine = ModelServerEngine()
        engine.baseURL = "http://127.0.0.1:\(Self.freePort())/v1"
        await engine.loadModel()
        XCTAssertEqual(engine.modelState, .unloaded)
        XCTAssertTrue(engine.loadFailureReason?.contains("No server answers") == true)
    }

    func testALaunchCommandThatExitsReportsItsStatus() async {
        let engine = ModelServerEngine()
        engine.baseURL = "http://127.0.0.1:\(Self.freePort())/v1"
        engine.launchCommand = "false"
        await engine.loadModel()
        XCTAssertEqual(engine.modelState, .unloaded)
        XCTAssertTrue(engine.loadFailureReason?.contains("exited with status 1") == true, engine.loadFailureReason ?? "")
    }

    // MARK: - Launch and transcribe

    /// The whole path: nothing answers, the launch command starts a server
    /// with `{model}` filled in, the engine waits for it, uploads the audio
    /// and reads the segments back.
    func testLaunchedServerTranscribesAFile() async throws {
        let dir = try makeTempDirectory(prefix: "ModelServerEngineTests")
        let script = dir.appendingPathComponent("fake_server.py")
        try Self.fakeServer.write(to: script, atomically: true, encoding: .utf8)
        let audio = dir.appendingPathComponent("meeting.wav")
        try Data("RIFF".utf8).write(to: audio)
        let port = Self.freePort()

        let engine = ModelServerEngine()
        engine.baseURL = "http://127.0.0.1:\(port)/v1"
        engine.model = "my-model"
        // A leading variable assignment, as real launch commands use for server settings.
        engine.launchCommand = "FAKE_PORT=\(port) python3 '\(script.path)' {model}"
        addTeardownBlock { engine.stopServer() }

        await engine.loadModel()
        XCTAssertEqual(engine.modelState, .loaded, engine.loadFailureReason ?? "")

        let segments = try await engine.transcribeSegments(audioPath: audio)
        XCTAssertEqual(segments.map(\.text), ["model my-model", "file meeting.wav"])
        XCTAssertTrue(engine.providesTimestamps)

        // Stopping must take the server down with the shell, or quitting the
        // app would leave it running.
        engine.stopServer()
        let probe = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/v1/models"))
        var stillUp = true
        for _ in 0 ..< 50 where stillUp {
            stillUp = (try? await URLSession.shared.data(from: probe)) != nil
            if stillUp { try await Task.sleep(for: .milliseconds(100)) }
        }
        XCTAssertFalse(stillUp, "the launched server must stop with the engine")
    }

    /// Answers `/v1/models` and `/v1/audio/transcriptions`, echoing the
    /// launch-time model argument and the uploaded file name as two segments.
    private static let fakeServer = #"""
    import http.server, json, os, re, sys
    port, model = int(os.environ["FAKE_PORT"]), sys.argv[1]
    class H(http.server.BaseHTTPRequestHandler):
        def log_message(self, *a): pass
        def reply(self, obj):
            body = json.dumps(obj).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        def do_GET(self):
            self.reply({"data": [{"id": model}]})
        def do_POST(self):
            data = self.rfile.read(int(self.headers["Content-Length"])).decode("latin-1")
            name = re.search(r'filename="([^"]+)"', data).group(1)
            self.reply({"text": "", "segments": [
                {"start": 0, "end": 1, "text": "model " + model},
                {"start": 1, "end": 2, "text": "file " + name}]})
    http.server.HTTPServer(("127.0.0.1", port), H).serve_forever()
    """#

    /// A port nothing listens on: bind to 0, read what the system picked, release it.
    private static func freePort() -> Int {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(sock) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(sock, $0, len) }
        }
        _ = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(sock, $0, &len) }
        }
        return Int(UInt16(bigEndian: addr.sin_port))
    }
}
