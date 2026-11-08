@preconcurrency import AVFoundation
import CoreAudio
import Foundation

/// Capture-time resampling for `AppAudioCapture`. Folds each CATap buffer to
/// 16 kHz mono before the file write (issue #379 follow-up) so a mid-recording
/// output-device rate change can't time-warp the track the way a single
/// post-hoc resample did. Extracted to a sibling file so `AppAudioCapture.swift`
/// stays under the 600-line lint cap — same pattern as
/// `AppAudioCapture+LiveSink.swift`.
@available(macOS 14.2, *)
extension AppAudioCapture {
    /// Format of the data written to the output fd: always 16 kHz mono. Read
    /// by `AudioCaptureSession` to describe the produced file.
    var outputSampleRate: Int {
        Int(speechSampleRate)
    }

    var outputChannels: Int {
        1
    }

    /// The buffer's hardware presentation time in mach ticks, for wall-clock
    /// gap-filling. Falls back to the callback clock if the IOProc didn't mark
    /// the host time valid.
    internal static func hostTicks(from time: UnsafePointer<AudioTimeStamp>) -> UInt64 {
        let stamp = time.pointee
        return stamp.mFlags.contains(.hostTimeValid) ? stamp.mHostTime : mach_absolute_time()
    }

    /// Resample + downmix one interleaved CATap buffer to 16 kHz mono and write
    /// it to `fd`, also forwarding the resampled buffer to the live sink. The
    /// converter is rebuilt on a mid-recording rate change. The resampler buffers
    /// internally, so a buffer that yields no output yet (converter priming) is
    /// simply not written — its samples emerge on a later call, no data lost.
    /// `hostTicks` is the buffer's hardware presentation time, used to fill
    /// device-restart gaps with silence so the track stays aligned to wall-clock.
    /// Runs on `writeQueue`.
    internal func writeCapturedBuffer(
        fd: Int32, data: UnsafeMutableRawPointer, byteCount: Int, hostTicks: UInt64,
    ) {
        let floatCount = byteCount / MemoryLayout<Float>.size
        let channels = max(actualChannels, 1)
        // A rate change is followed from the buffer that confirms it, not from
        // the next one, which is why this hands back the rate to use here.
        let inputRate = adoptDeliveredRate(frames: floatCount / channels, hostTicks: hostTicks)
        let interleaved = Array(UnsafeBufferPointer(
            start: data.assumingMemoryBound(to: Float.self), count: floatCount,
        ))
        resampleForwardAndWrite(
            fd: fd, interleaved: interleaved,
            inputRate: inputRate, inputChannels: channels,
            hostTicks: hostTicks,
        )
    }

    /// Core of `writeCapturedBuffer`, parameterised on the input rate/channels so
    /// it's drivable without a live CATap. Resamples to 16 kHz mono, fills any
    /// device-restart gap with silence (file only — the live path doesn't need
    /// gap-fill), writes the resampled samples to `fd`, and forwards those same
    /// samples to the live sink.
    internal func resampleForwardAndWrite(
        fd: Int32, interleaved: [Float], inputRate: Int, inputChannels: Int, hostTicks: UInt64,
    ) {
        let mono16k = resampler.process(
            interleaved, inputRate: inputRate, inputChannels: inputChannels,
        )
        guard !mono16k.isEmpty else { return }
        fillTimelineGap(fd: fd, hostTicks: hostTicks, outputFrames: mono16k.count)
        Self.writeFloats(mono16k, to: fd)
        forwardToLiveSink(monoSamples: mono16k)
    }

    /// Write silence for a device-restart gap before this buffer's audio, so the
    /// app track stays aligned to wall-clock (issue #379 follow-up). Mirrors
    /// `MicCaptureHandler.fillTimelineGap`; the `TimelineAnchor` self-anchors on
    /// the first buffer and is never reset, so only a real gap produces silence.
    private func fillTimelineGap(fd: Int32, hostTicks: UInt64, outputFrames: Int) {
        let silence = timelineAnchor.silenceFramesBefore(
            hostSeconds: machTicksToSeconds(hostTicks), frameCount: outputFrames,
        )
        guard silence > 0 else { return }
        Self.writeFloats([Float](repeating: 0, count: silence), to: fd)
    }

    /// Write a float buffer's raw bytes to `fd` in one POSIX write loop.
    private static func writeFloats(_ samples: [Float], to fd: Int32) {
        samples.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                writeAllToFileHandle(fd, base, count: raw.count)
            }
        }
    }
}
