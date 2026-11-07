import Foundation
import os.log

/// Centralized path constants and logger subsystem for the app.
enum AppPaths {
    /// Logger subsystem for all os.log loggers.
    static let logSubsystem = "com.earshot"

    /// App data directory: `~/Library/Application Support/Earshot/`
    /// In sandbox, this automatically resolves to the container path.
    /// Falls back to `~/.Earshot/` if Application Support is unavailable.
    static let dataDir: URL = {
        if let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return appSupport.appendingPathComponent("Earshot", isDirectory: true)
        }
        Logger(subsystem: logSubsystem, category: "AppPaths")
            .error("Application Support directory unavailable — falling back to home directory")
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".Earshot", isDirectory: true)
    }()

    /// IPC directory: under `dataDir` for sandbox compatibility.
    static let ipcDir = dataDir.appendingPathComponent("ipc", isDirectory: true)

    /// Recordings directory.
    static let recordingsDir = dataDir.appendingPathComponent("recordings", isDirectory: true)

    /// Protocols output directory (legacy, inside Application Support).
    static let protocolsDir = dataDir.appendingPathComponent("protocols", isDirectory: true)

    /// Default protocols output in Downloads: `~/Downloads/Earshot/`
    /// In sandbox, `FileManager.urls(for: .downloadsDirectory)` resolves to the container-granted path.
    static let downloadsProtocolsDir: URL = {
        guard let downloads = FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask).first
        else {
            return protocolsDir
        }
        return downloads.appendingPathComponent("Earshot", isDirectory: true)
    }()

    /// Speaker voice profiles DB.
    static let speakersDB = dataDir.appendingPathComponent("speakers.json")

    /// Custom protocol prompt file.
    static let customPromptFile = dataDir.appendingPathComponent("protocol_prompt.md")

    /// Exists exactly while a run of this bundle is alive; see `LivenessMarker`.
    /// Named per bundle identifier because the dev and release builds share
    /// `dataDir`, and each must judge only its own previous run: one build's
    /// leftover must not read as the other's crash. Kept out of
    /// `recordingsDir`, which is scanned for crash signatures by filename.
    static let livenessMarker = dataDir
        .appendingPathComponent("\(Bundle.main.bundleIdentifier ?? "Earshot").running")

    /// Legacy IPC directory (`~/.meeting-transcriber/`) used before sandbox migration.
    private static let legacyIpcDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".meeting-transcriber", isDirectory: true)

    private static let logger = Logger(subsystem: logSubsystem, category: "AppPaths")

    /// Moves the data folder and the default notes folder from their names
    /// before the rename to Earshot, leaving a symlink at each old path so
    /// absolute paths stored in queue snapshots and settings still resolve.
    /// Runs before anything reads `dataDir`.
    static func migrateRenamedFolders() {
        let fm = FileManager.default
        for directory: FileManager.SearchPathDirectory in [.applicationSupportDirectory, .downloadsDirectory] {
            guard let base = fm.urls(for: directory, in: .userDomainMask).first else { continue }
            moveLegacyFolder(
                base.appendingPathComponent("MeetingTranscriber", isDirectory: true),
                to: base.appendingPathComponent("Earshot", isDirectory: true),
            )
        }
    }

    /// Moves `old` to `new` and links `old` to it, unless `new` exists or
    /// `old` is missing or already a link.
    static func moveLegacyFolder(_ old: URL, to new: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path),
              (try? old.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true
        else { return }
        do {
            try fm.moveItem(at: old, to: new)
            try fm.createSymbolicLink(at: old, withDestinationURL: new)
        } catch {
            logger.error("Moving \(old.path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Migrate IPC files from `~/.meeting-transcriber/` to `dataDir/ipc/`.
    /// Safe to call multiple times — copyItem fails gracefully if destination exists.
    /// The folders are parameters so the migration can be exercised on temp
    /// folders rather than on the user's own.
    static func migrateIfNeeded(from legacyIpcDir: URL = legacyIpcDir, to ipcDir: URL = ipcDir) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: legacyIpcDir.path) else { return }

        let filesToMigrate = [
            "processed_recordings.json",
            "pipeline_queue.json",
            "pipeline_log.jsonl",
        ]

        try? fm.createDirectory(at: ipcDir, withIntermediateDirectories: true)

        for name in filesToMigrate {
            let src = legacyIpcDir.appendingPathComponent(name)
            let dst = ipcDir.appendingPathComponent(name)
            do {
                try fm.copyItem(at: src, to: dst)
                logger.info("Migrated \(name) from legacy IPC directory")
            } catch CocoaError.fileWriteFileExists {
                // Already migrated — expected on subsequent launches
            } catch CocoaError.fileReadNoSuchFile {
                // Source doesn't exist — skip
            } catch {
                logger.error("Failed to migrate \(name): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
