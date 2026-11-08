#if !APPSTORE

    @testable import Earshot
    import XCTest

    @MainActor
    final class MeetingsMCPServerTests: XCTestCase {
        private func makeLibrary() throws -> MeetingLibrary {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mcp-\(UUID())")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
            try "# Budget review\n\n## Decisions\n- cut travel".write(
                to: folder.appendingPathComponent("20261102_0930_budget_review.md"), atomically: true, encoding: .utf8,
            )
            try "[00:01] Ann: we cut travel".write(
                to: folder.appendingPathComponent("20261102_0930_budget_review.txt"), atomically: true, encoding: .utf8,
            )
            return MeetingLibrary { folder }
        }

        // swiftlint:disable:next discouraged_optional_collection
        private func call(_ method: String, library: MeetingLibrary, _ params: [String: Any] = [:]) -> [String: Any]? {
            MeetingsMCPServer.respond(to: ["jsonrpc": "2.0", "id": 1, "method": method, "params": params], library: library)
        }

        private func text(_ reply: [String: Any]?) -> String? { // swiftlint:disable:this discouraged_optional_collection
            ((reply?["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String
        }

        func testInitializeEchoesTheProtocolVersionAndOffersTools() throws {
            let library = try makeLibrary()
            let result = call("initialize", library: library, ["protocolVersion": "2025-03-26"])?["result"] as? [String: Any]

            XCTAssertEqual(result?["protocolVersion"] as? String, "2025-03-26")
            let tools = (call("tools/list", library: library)?["result"] as? [String: Any])?["tools"] as? [[String: Any]]
            XCTAssertEqual(tools?.compactMap { $0["name"] as? String }, ["list_meetings", "get_meeting"])
        }

        func testListSearchesAndGetReadsBothParts() throws {
            let library = try makeLibrary()

            let list = text(call("tools/call", library: library, ["name": "list_meetings", "arguments": ["query": "travel"]]))
            XCTAssertEqual(list?.hasPrefix("20261102_0930_budget_review | "), true)
            XCTAssertEqual(text(call("tools/call", library: library, ["name": "list_meetings", "arguments": ["query": "zebra"]])), "No meetings found.")

            let both = text(call(
                "tools/call", library: library, ["name": "get_meeting", "arguments": ["id": "20261102_0930_budget_review", "part": "both"]],
            ))
            XCTAssertEqual(both?.contains("- cut travel"), true)
            XCTAssertEqual(both?.contains("## Transcript\n\n[00:01] Ann: we cut travel"), true)
        }

        func testNotificationsGetNoReplyAndUnknownMethodsAnError() throws {
            let library = try makeLibrary()

            XCTAssertNil(MeetingsMCPServer.respond(to: ["jsonrpc": "2.0", "method": "notifications/initialized"], library: library))
            XCTAssertNotNil(call("resources/list", library: library)?["error"])
        }

        func testOnlyTheMCPFlagStartsTheServer() {
            XCTAssertNil(MeetingsMCPServer.folder(arguments: ["Earshot", "--auto-watch"]))
            XCTAssertEqual(MeetingsMCPServer.folder(arguments: ["Earshot", "--mcp", "/tmp/notes"])?.path, "/tmp/notes")
        }
    }

#endif
