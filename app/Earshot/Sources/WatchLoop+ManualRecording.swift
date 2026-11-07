import Foundation
import os.log

private let logger = Logger(subsystem: AppPaths.logSubsystem, category: "WatchLoop")

/// The poll loop that decides when a manually started recording ends, split out
/// of `WatchLoop.swift` to keep that file under the line cap.
///
/// Only the monitor moved. The start and stop paths mutate `activeRecorder`,
/// `manualRecordingTask` and `watchTask`, all of which are private to the class
/// on purpose, and moving them here would mean widening those to internal for a
/// line count. The monitor reads nothing but injected dependencies.
extension WatchLoop {
    /// Polls until the recorded app exits or the recording runs past
    /// `maxDuration`, then stops it. An exit wins a tie, so a process that
    /// dies right at the cap reads as a clean exit. No PID means a
    /// microphone-only recording: nothing can exit, so only the cap stops it.
    func monitorManualRecording(pid: pid_t?) async {
        let startTime = nowProvider()
        while !Task.isCancelled {
            if let pid, !pidAliveCheck(pid) {
                logger.info("Monitored app (PID \(pid)) exited — stopping manual recording")
                stopManualRecording()
                return
            }
            if nowProvider().timeIntervalSince(startTime) > maxDuration {
                logger.info("Max recording duration reached — stopping manual recording")
                stopManualRecording()
                return
            }
            try? await sleepProvider(pollInterval)
        }
    }
}
