import Foundation

/// Pure scheduling decisions for the daily heartbeat. Kept UTC-based and free
/// of wall-clock reads so it is deterministic and unit-testable; the app layer
/// supplies `now` and the persisted last-sent day.
public enum HeartbeatSchedule {

    /// Wait this long after launch before the first send check, so telemetry
    /// never races login, network bring-up, or the first-run notice.
    public static let launchDelay: TimeInterval = 30

    /// How often the running app re-checks whether a new UTC day has started.
    /// Hourly is plenty: the decision is idempotent (one send per day).
    public static let recheckInterval: TimeInterval = 3600

    /// The UTC calendar day as "yyyy-MM-dd". Aligns with PostHog's daily active
    /// buckets and is timezone-independent, so two Macs in different zones agree
    /// on the day boundary.
    public static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// True when no heartbeat has been sent for the current UTC day.
    public static func shouldSend(lastSentDay: String?, now: Date) -> Bool {
        guard let lastSentDay else { return true }
        return lastSentDay != dayKey(for: now)
    }

    /// After the notice is first shown, hold the very first send until the user
    /// has had a real chance to opt out: either a later app launch, or 24 hours,
    /// whichever comes first. A menu-bar app can run for weeks, so "next launch"
    /// alone could delay data indefinitely; the 24h fallback keeps it timely.
    ///
    /// - Parameter noticeShownThisSession: true only when the notice was shown
    ///   during the current process. If it was shown in a previous session, a
    ///   launch has already happened, so the window has passed.
    public static func coolingOffElapsed(
        noticeShownThisSession: Bool,
        noticeShownAt: Date?,
        now: Date
    ) -> Bool {
        guard noticeShownThisSession else { return true }
        guard let noticeShownAt else { return true }
        return now.timeIntervalSince(noticeShownAt) >= 24 * 3600
    }
}
