import AudioTapLib
import Foundation

/// Abstraction for recording, enabling mock injection in tests.
@MainActor
protocol RecordingProvider {
    func start(source: RecordingSource, micDeviceUID: String?) throws
    func stop() throws -> RecordingResult

    /// `stop()` with the file work (reading the tracks back, mixing, writing
    /// the mix) off the main actor. Ending the capture itself still happens on
    /// the caller's actor. Used where the main thread has to be free while the
    /// mix runs: a quit, whose time budget is a timer on the main actor, and
    /// the mix of a long recording takes seconds. Default: the synchronous
    /// `stop()`, for doubles that have no file work to move.
    func stopOffMain() async throws -> RecordingResult

    /// Each channel's level, buffer ages and failure flags, read together so
    /// one polling tick decides from one moment. Default: both channels
    /// delivering signal right now, so a double that does not simulate capture
    /// never looks broken; it has to say so before it can be reported.
    var captureStatus: CaptureStatus { get }
}

extension CaptureStatus {
    /// Both channels delivered a buffer carrying signal just now, at -120 dBFS.
    /// What a provider reports when it does not simulate capture at all.
    static let deliveringNow = CaptureStatus(
        mic: CaptureChannelStatus(ages: .deliveringSignalNow),
        app: CaptureChannelStatus(ages: .deliveringSignalNow),
    )

    subscript(channel: AudioChannel) -> CaptureChannelStatus {
        switch channel {
        case .mic: mic
        case .app: app
        }
    }
}

extension ChannelSignalAges {
    /// A channel that delivered a buffer carrying signal just now.
    static let deliveringSignalNow = ChannelSignalAges(secondsSinceLastBuffer: 0, secondsSinceLastEnergy: 0)
}

extension RecordingProvider {
    // Async only to satisfy the requirement: a double has no file work to
    // move, so its stop stays where it is called.
    // swiftlint:disable:next async_without_await
    func stopOffMain() async throws -> RecordingResult {
        try stop()
    }

    var captureStatus: CaptureStatus {
        .deliveringNow
    }
}
