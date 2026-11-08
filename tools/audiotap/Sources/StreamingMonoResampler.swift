@preconcurrency import AVFoundation
import Foundation
import os.log

private let logger = Logger(subsystem: "com.earshot.audiotap", category: "StreamingMonoResampler")

/// Converts interleaved float32 capture buffers to mono Float32 at a fixed
/// target rate, rebuilding the underlying `AVAudioConverter` whenever the input
/// sample rate changes.
///
/// A mid-recording output-device change can renegotiate the capture rate (e.g.
/// 48 kHz → 24 kHz). Resampling every span with one rate — as the batch app
/// path historically did — time-warps every span that wasn't at that rate
/// (issue #379 "tape-stop" drift: a 24 kHz span played as 48 kHz comes out 2×
/// too fast and an octave low). Converting each buffer at the rate that was live
/// when it arrived keeps the written track at true real-time duration. Mirrors
/// the in-callback resampling `MicCaptureHandler` already does for the mic track.
///
/// Channels are folded to mono by averaging *before* the converter (matching
/// `DualSourceRecorder.downmixToMono` — `AVAudioConverter`'s own stereo→mono
/// keeps only channel 0), so the converter does pure rate conversion and a
/// channel-count change across a device swap needs no special handling.
///
/// Not thread-safe: drive it from a single serial context (the capture IOProc's
/// `writeQueue`).
final class StreamingMonoResampler {
    private let outputFormat: AVAudioFormat
    private var converter: AVAudioConverter?
    private var inputRate = 0

    init(targetRate: Int) {
        guard targetRate > 0, let output = AVAudioFormat(
            standardFormatWithSampleRate: Double(targetRate), channels: 1,
        ) else { preconditionFailure("no mono Float32 format at \(targetRate) Hz") }
        outputFormat = output
    }

    /// Convert one interleaved buffer (`inputChannels` channels at `inputRate`)
    /// to mono samples at the target rate. A change in `inputRate` from the
    /// previous call rebuilds the converter so resampling state stays continuous
    /// within a span but never carries a stale rate across a device swap.
    /// Returns `[]` for empty input or when a converter can't be built.
    func process(_ samples: [Float], inputRate: Int, inputChannels: Int) -> [Float] {
        guard !samples.isEmpty, inputRate > 0, inputChannels > 0 else { return [] }

        let mono = downmixToMono(samples, channels: inputChannels)
        guard !mono.isEmpty, let converter = ensureConverter(rate: inputRate) else { return [] }

        let inputFrames = AVAudioFrameCount(mono.count)
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: converter.inputFormat, frameCapacity: inputFrames)
        else { return [] }
        inputBuffer.frameLength = inputFrames
        if let channel = inputBuffer.floatChannelData?[0] {
            mono.withUnsafeBufferPointer { src in
                if let base = src.baseAddress {
                    channel.update(from: base, count: mono.count)
                }
            }
        }

        let ratio = outputFormat.sampleRate / Double(inputRate)
        let outputCapacity = resampleOutputCapacity(inputFrames: inputFrames, ratio: ratio)
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat, frameCapacity: outputCapacity,
        ) else { return [] }

        var error: NSError?
        let feed = FeedOnce(buffer: inputBuffer)
        let status = converter.convert(to: outputBuffer, error: &error) { _, inStatus in
            feed.next(inStatus)
        }
        if let error {
            logger.warning("App resample error: \(error.localizedDescription, privacy: .public)")
            return []
        }
        guard status != .error, outputBuffer.frameLength > 0,
              let outPtr = outputBuffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: outPtr, count: Int(outputBuffer.frameLength)))
    }

    private func ensureConverter(rate: Int) -> AVAudioConverter? {
        if let converter, rate == inputRate { return converter }
        guard let input = AVAudioFormat(
            standardFormatWithSampleRate: Double(rate), channels: 1,
        ), let conv = AVAudioConverter(from: input, to: outputFormat) else {
            logger.error("Failed to build resampler for \(rate) Hz")
            return nil
        }
        converter = conv
        inputRate = rate
        return conv
    }
}

/// Single-shot input provider for `AVAudioConverter.convert(to:error:withInputFrom:)`.
/// First call returns the buffer with `.haveData`; subsequent calls return
/// `.noDataNow` so the converter stops asking. Reference-typed because the
/// converter's input callback is `@Sendable` and would reject a mutating-var
/// capture. `internal` — `MicCaptureHandler`'s tap converter uses the same
/// provider.
final class FeedOnce: @unchecked Sendable {
    private let buffer: AVAudioPCMBuffer
    private var fed = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(_ outStatus: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        if fed {
            outStatus.pointee = .noDataNow
            return nil
        }
        fed = true
        outStatus.pointee = .haveData
        return buffer
    }
}
