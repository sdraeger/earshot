@testable import Earshot
import Foundation

/// Scriptable `UtteranceBoundaryDetecting`: returns the next scripted event per
/// chunk (nil = no boundary), so tests drive utterance segmentation
/// deterministically without the Silero model.
actor ScriptedBoundaryDetector: UtteranceBoundaryDetecting {
    private var script: [FluidVAD.StreamEvent.Kind?]

    init(script: [FluidVAD.StreamEvent.Kind?]) {
        self.script = script
    }

    // swiftlint:disable:next async_without_await
    func boundary(in _: [Float]) async -> FluidVAD.StreamEvent.Kind? {
        script.isEmpty ? nil : script.removeFirst()
    }

    // swiftlint:disable:next async_without_await
    func reset() async {}
}
