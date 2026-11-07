@testable import Earshot
import Foundation

extension EngineController {
    /// Engines for a view test: no old-models row, so nothing binds to the
    /// real `Documents` and Trash. Pass `legacyModels` to show one.
    @MainActor
    static func forTesting(settings: AppSettings, legacyModels: LegacyWhisperModelsState? = nil) -> EngineController {
        EngineController(settings: settings) { _ in legacyModels }
    }
}
