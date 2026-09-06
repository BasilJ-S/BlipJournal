import Foundation

/// Decides whether returning to the foreground should put the lock back up.
///
/// A pure value so the rule is testable without a scene, a clock, or biometrics.
struct LockPolicy: Equatable {
    /// How long the app may sit in the background before it relocks, in seconds.
    var gracePeriod: TimeInterval = 30

    /// True when the app should lock on returning to the foreground.
    ///
    /// A nil `backgroundedAt` means the app never went to the background, so nothing
    /// changes. Elapsed time at or beyond the grace period locks.
    func shouldLock(backgroundedAt: Date?, now: Date) -> Bool {
        guard let backgroundedAt else { return false }
        return now.timeIntervalSince(backgroundedAt) >= gracePeriod
    }
}
