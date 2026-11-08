import CoreAudio
import Foundation

/// Live-buffer forwarding for `AppAudioCapture`. Extracted to a sibling file so
/// `AppAudioCapture.swift` stays under the 600-line lint cap; same pattern as
/// `AppAudioCapture+PIDTranslation.swift`.
@available(macOS 14.2, *)
extension AppAudioCapture {
    /// Hand already-resampled 16 kHz mono samples to the optional live sink —
    /// the same data `writeCapturedBuffer` writes to the file fd, so the app
    /// side never resamples. Gap-fill
    /// silence is deliberately excluded; only the buffer's real samples flow
    /// here. Short-circuits when no sink is installed.
    func forwardToLiveSink(monoSamples: [Float]) {
        guard let sink = liveSink, !monoSamples.isEmpty else { return }
        sink(LiveAudioBuffer(
            samples: monoSamples,
            channelCount: 1,
            sampleRate: Int(speechSampleRate),
            hostTime: mach_absolute_time(),
        ))
    }
}
