import Foundation

/// One capture channel as the polling path sees it.
public struct CaptureChannelStatus: Equatable, Sendable {
    /// Instantaneous level in dBFS, decayed to -120 when no buffer arrived in
    /// the last 0.5 s, and -120 for a channel never opened.
    public var levelDBFS: Double
    /// How long the channel has gone without a buffer, and without one
    /// carrying signal. The level cannot say this: it reads -120 for a muted
    /// device, a dead tap and a channel never opened alike.
    public var ages: ChannelSignalAges
    /// Abandoned for good (issue #588): a restart never returned or the retry
    /// budget ran out. A silent channel may come back; one that gave up will not.
    public var gaveUp: Bool

    public init(levelDBFS: Double = -120, ages: ChannelSignalAges = .unknown, gaveUp: Bool = false) {
        self.levelDBFS = levelDBFS
        self.ages = ages
        self.gaveUp = gaveUp
    }
}

/// Everything a capture session reports about its channels, read in one go
/// so every decision of one polling tick sees the same moment.
public struct CaptureStatus: Equatable, Sendable {
    public var mic: CaptureChannelStatus
    public var app: CaptureChannelStatus
    /// The microphone's give-up was a first start that missed its deadline
    /// (issue #778), not a failed restart. Only the notice's wording depends on it.
    public var micStartTimedOut: Bool
    /// Whether the microphone is released for lack of audio, and how often it
    /// was (issues #724, #706). Unlike a give-up it clears on a device change.
    public var micStall: MicCaptureStall
    /// The opt-in silent-track watchdog stopped rebuilding the app tap because
    /// rebuilds did not restore signal (issue #672). The channel still captures.
    public var appWatchdogGaveUp: Bool
    /// The app tap's noise-floor verdict (issue #699), see `AppNoiseFloorSensor`.
    public var appNoiseFloorOnly: Bool

    public init(
        mic: CaptureChannelStatus = .init(),
        app: CaptureChannelStatus = .init(),
        micStartTimedOut: Bool = false,
        micStall: MicCaptureStall = MicCaptureStall(),
        appWatchdogGaveUp: Bool = false,
        appNoiseFloorOnly: Bool = false,
    ) {
        self.mic = mic
        self.app = app
        self.micStartTimedOut = micStartTimedOut
        self.micStall = micStall
        self.appWatchdogGaveUp = appWatchdogGaveUp
        self.appNoiseFloorOnly = appNoiseFloorOnly
    }

    /// No session: both channels silent and never opened.
    public static let idle = Self()
}
