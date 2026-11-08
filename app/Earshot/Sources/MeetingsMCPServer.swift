#if !APPSTORE

    import Foundation

    /// A Model Context Protocol server over stdio, started as `Earshot --mcp
    /// [folder]`, that lets Claude list, search and read the meetings in the
    /// notes folder (the app's output folder by default). It reads files only
    /// and runs without the app.
    @MainActor
    enum MeetingsMCPServer {
        /// The folder `--mcp` names, or the app's, when the arguments ask for
        /// the server; nil otherwise.
        static func folder(arguments: [String]) -> URL? {
            guard let index = arguments.firstIndex(of: "--mcp") else { return nil }
            if index + 1 < arguments.count, !arguments[index + 1].hasPrefix("-") {
                return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
            }
            return AppSettings().effectiveOutputDir.appendingPathComponent("protocols", isDirectory: true)
        }

        /// Answers newline-delimited JSON-RPC requests until stdin closes.
        static func run(folder: URL) {
            let library = MeetingLibrary { folder }
            while let line = readLine() {
                guard let data = line.data(using: .utf8),
                      let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let reply = respond(to: request, library: library),
                      let out = try? JSONSerialization.data(withJSONObject: reply)
                else { continue }
                FileHandle.standardOutput.write(out + Data("\n".utf8))
            }
        }

        /// The reply to one request, nil for a notification.
        static func respond(
            to request: [String: Any], library: MeetingLibrary,
        ) -> [String: Any]? { // swiftlint:disable:this discouraged_optional_collection
            guard let id = request["id"] else { return nil }
            let method = request["method"] as? String ?? ""
            let params = request["params"] as? [String: Any] ?? [:]
            let result: [String: Any]
            switch method {
            case "initialize":
                result = [
                    "protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                    "capabilities": ["tools": [:]],
                    "serverInfo": ["name": "earshot", "version": "1"],
                ]

            case "ping":
                result = [:]

            case "tools/list":
                result = ["tools": tools]

            case "tools/call":
                library.reload()
                let arguments = params["arguments"] as? [String: Any] ?? [:]
                let (text, isError) = call(params["name"] as? String ?? "", arguments, library)
                result = ["content": [["type": "text", "text": text]], "isError": isError]

            default:
                return ["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Unknown method \(method)"]]
            }
            return ["jsonrpc": "2.0", "id": id, "result": result]
        }

        private static func call(_ name: String, _ arguments: [String: Any], _ library: MeetingLibrary) -> (String, Bool) {
            switch name {
            case "list_meetings":
                let query = arguments["query"] as? String ?? ""
                let limit = arguments["limit"] as? Int ?? 50
                let found = library.meetings.filter { library.matches($0, query: query) }.prefix(limit)
                let lines = found.map { "\($0.id) | \($0.date.formatted(date: .abbreviated, time: .shortened)) | \($0.title)" }
                return (lines.isEmpty ? "No meetings found." : lines.joined(separator: "\n"), false)

            case "get_meeting":
                guard let id = arguments["id"] as? String, let meeting = library.meetings.first(where: { $0.id == id }) else {
                    return ("No meeting with that id. Call list_meetings for the ids.", true)
                }
                let part = arguments["part"] as? String ?? "notes"
                let notes = part == "transcript" ? nil : library.notes(of: meeting)
                let transcript = part == "notes" ? nil : library.transcript(of: meeting)
                let text = [notes, transcript.map { "## Transcript\n\n\($0)" }].compactMap(\.self).joined(separator: "\n\n")
                return (text.isEmpty ? "This meeting has no \(part)." : text, false)

            default:
                return ("Unknown tool \(name)", true)
            }
        }

        private static let tools: [[String: Any]] = [
            [
                "name": "list_meetings",
                "description": "List the user's recorded meetings, newest first, as `id | date | title`. "
                    + "With `query`, only meetings whose title, notes or transcript contain it.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string", "description": "Text to search for, case-insensitive"],
                        "limit": ["type": "integer", "description": "Most meetings to return (default 50)"],
                    ],
                ],
            ],
            [
                "name": "get_meeting",
                "description": "Read one meeting's notes (summary, decisions, tasks), its full transcript, or both.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string", "description": "The id from list_meetings"],
                        "part": ["type": "string", "enum": ["notes", "transcript", "both"]],
                    ],
                    "required": ["id"],
                ],
            ],
        ]
    }

#endif
