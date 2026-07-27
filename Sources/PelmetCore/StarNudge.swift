import Foundation

/// Pure policy for the "star us on GitHub" nudge. Kept free of wall-clock reads
/// so it is deterministic and unit-testable; the app layer supplies `now` and
/// the persisted state. The nudge is a gentle, hard-rate-limited ask: it never
/// appears on first launch, only after the user has gotten real value from the
/// app, and it stops for good once accepted, declined, or shown a few times.
public enum StarNudgePolicy {

    /// Minimum time after the first launch before the first ask. Long enough
    /// that the user has lived with Pelmet, never on day one.
    public static let initialDelay: TimeInterval = 3 * 24 * 3600

    /// Minimum time between reminders once the first ask has been shown.
    public static let reminderInterval: TimeInterval = 14 * 24 * 3600

    /// Hard cap on how many times the nudge is ever shown.
    public static let maxShows = 3

    /// Decides whether the nudge may be shown right now.
    ///
    /// - Parameters:
    ///   - firstLaunchAt: when the app first launched; nil before it is seeded.
    ///   - hasManagedItems: whether the user has actually hidden icons at least
    ///     once (the satisfaction signal).
    ///   - dismissedPermanently: set once the user stars, opts out, or the cap
    ///     is reached; a true value stops the nudge forever.
    ///   - lastShownAt: when the nudge was last shown; nil until the first show.
    ///   - showCount: how many times it has already been shown.
    ///   - now: the current time.
    public static func shouldShow(
        firstLaunchAt: Date?,
        hasManagedItems: Bool,
        dismissedPermanently: Bool,
        lastShownAt: Date?,
        showCount: Int,
        now: Date
    ) -> Bool {
        guard !dismissedPermanently,
              hasManagedItems,
              let firstLaunchAt,
              showCount < maxShows
        else { return false }

        if showCount == 0 {
            return now.timeIntervalSince(firstLaunchAt) >= initialDelay
        }

        guard let lastShownAt else { return false }
        return now.timeIntervalSince(lastShownAt) >= reminderInterval
    }
}
