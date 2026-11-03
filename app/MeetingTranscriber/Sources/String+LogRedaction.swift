import CryptoKit
import Foundation

extension String {
    /// Deterministic 4-hex-char pseudonym derived from SHA-256.
    /// Stable across runs (same input → same output) so logs can be correlated
    /// without exposing the clear name. Used for speaker IDs in diagnostic logs.
    var pseudonymized: String {
        guard !isEmpty else { return "speaker_anon" }
        let hash = SHA256.hash(data: Data(utf8))
        let prefix = hash.prefix(2).map { String(format: "%02x", $0) }.joined()
        return "speaker_\(prefix)"
    }
}
