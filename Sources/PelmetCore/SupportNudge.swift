import Foundation

/// Pure policy for the "support Pelmet" nudge. It follows the star nudge so
/// users are not asked for two things at once, then uses a longer reminder
/// interval and a lower cap because financial asks should stay occasional.
public enum SupportNudgePolicy {

    /// The app must have had time to provide value before asking for support.
    public static let initialDelay: TimeInterval = 3 * 24 * 3600

    /// Breathing room after the star nudge reaches a permanent outcome.
    public static let graceAfterStarNudge: TimeInterval = 7 * 24 * 3600

    /// Minimum time between support reminders.
    public static let reminderInterval: TimeInterval = 30 * 24 * 3600

    /// Hard cap on how many times the support nudge is ever shown.
    public static let maxShows = 2

    /// Decides whether the support nudge may be shown right now.
    public static func shouldShow(
        firstLaunchAt: Date?,
        hasManagedItems: Bool,
        starNudgeDismissed: Bool,
        starNudgeLastShownAt: Date?,
        dismissedPermanently: Bool,
        lastShownAt: Date?,
        showCount: Int,
        now: Date
    ) -> Bool {
        guard !dismissedPermanently,
              hasManagedItems,
              let firstLaunchAt,
              starNudgeDismissed,
              let starNudgeLastShownAt,
              showCount < maxShows,
              now.timeIntervalSince(starNudgeLastShownAt) >= graceAfterStarNudge
        else { return false }

        if showCount == 0 {
            return now.timeIntervalSince(firstLaunchAt) >= initialDelay
        }

        guard let lastShownAt else { return false }
        return now.timeIntervalSince(lastShownAt) >= reminderInterval
    }
}
