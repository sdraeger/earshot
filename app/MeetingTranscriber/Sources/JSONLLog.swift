import Foundation
import os.log

private let logger = Logger(subsystem: AppPaths.logSubsystem, category: "JSONLLog")

/// An event stored one JSON object per line, with the timestamp `loadRecent` filters on.
protocol JSONLLogEvent: Codable {
    var ts: Date { get }
    /// File name under the app's data folder.
    static var logFileName: String { get }
}

extension RecognitionEvent: JSONLLogEvent {
    static let logFileName = "recognition_log.jsonl"
}

extension StageTimingEvent: JSONLLogEvent {
    static let logFileName = "stage_timing.jsonl"
}

typealias RecognitionStatsLog = JSONLLog<RecognitionEvent>
typealias StageTimingLog = JSONLLog<StageTimingEvent>

/// Append-only JSONL writer. One file per app install, owner-readable (chmod
/// 0600 on first creation). Production callers use `init()`; tests pass an
/// explicit `path:` to avoid polluting the real log.
actor JSONLLog<Event: JSONLLogEvent> {
    static var defaultPath: URL {
        AppPaths.dataDir.appendingPathComponent(Event.logFileName)
    }

    private let path: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(path: URL) {
        self.path = path
        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    init() {
        self.init(path: Self.defaultPath)
    }

    func append(_ events: [Event]) {
        guard !events.isEmpty else { return }
        do {
            try FileManager.default.createDirectory(
                at: path.deletingLastPathComponent(), withIntermediateDirectories: true,
            )
            if !FileManager.default.fileExists(atPath: path.path) {
                FileManager.default.createFile(
                    atPath: path.path, contents: nil,
                    attributes: [.posixPermissions: 0o600],
                )
            }
            let handle = try FileHandle(forWritingTo: path)
            defer { try? handle.close() }
            try handle.seekToEnd()
            for event in events {
                try handle.write(contentsOf: encoder.encode(event) + Data([0x0A]))
            }
            try handle.synchronize()
        } catch {
            logger.error("Failed to append \(Event.logFileName, privacy: .public) events: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Events with `ts` within the last `interval` seconds. Skips lines that
    /// fail to decode (forward-compat for future schema changes).
    func loadRecent(within interval: TimeInterval, now: Date = Date()) -> [Event] {
        guard let data = try? Data(contentsOf: path),
              let text = String(data: data, encoding: .utf8) else { return [] }
        let cutoff = now.addingTimeInterval(-interval)
        return text.split(separator: "\n").compactMap { line in
            guard let event = try? decoder.decode(Event.self, from: Data(line.utf8)), event.ts >= cutoff else { return nil }
            return event
        }
    }
}
