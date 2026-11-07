import Foundation

/// When a detector may report a meeting: once its key has been seen in
/// `threshold` consecutive polls, and not while the key cools down after its
/// last meeting ended. Shared by both detectors so the rule lives in one place.
struct DetectionConfirmation {
    private let threshold: Int
    private let cooldown: TimeInterval = 5
    private var consecutiveHits: [String: Int] = [:]
    private var cooldownUntil: [String: Date] = [:]

    init(threshold: Int) {
        self.threshold = threshold
    }

    func isCoolingDown(_ key: String, now: Date = Date()) -> Bool {
        cooldownUntil[key].map { now < $0 } ?? false
    }

    /// Ends one poll: counts each key seen in it and zeroes every other key,
    /// so only consecutive polls add up, then returns the confirmed keys.
    mutating func endRound(seen: Set<String>) -> Set<String> {
        for key in consecutiveHits.keys where !seen.contains(key) {
            consecutiveHits[key] = 0
        }
        for key in seen {
            consecutiveHits[key, default: 0] += 1
        }
        return seen.filter { consecutiveHits[$0, default: 0] >= threshold }
    }

    /// Forgets every count, and holds `key`'s meeting off for the cooldown so
    /// the call that just ended is not detected again on its way out.
    mutating func reset(coolingDown key: String?, now: Date = Date()) {
        consecutiveHits.removeAll()
        if let key {
            cooldownUntil[key] = now.addingTimeInterval(cooldown)
        }
    }
}
