import Foundation

/// Persisted portion of an update-check recovery episode.
///
/// Sparkle records a failed scheduled check as the latest check time, so a
/// transient offline moment otherwise postpones the next attempt for a day.
/// This snapshot survives a Pelmet relaunch and lets the app resume a small,
/// bounded recovery sequence without replacing Sparkle's normal scheduler.
public struct UpdateRetrySnapshot: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, Sendable {
        case waitingForConnectivity
        case scheduled
        case checking
    }

    /// Number of recovery checks already started, not including Sparkle's
    /// original scheduled check.
    public var attemptCount: Int
    public var mode: Mode
    public var nextRetryDate: Date?

    public init(attemptCount: Int, mode: Mode, nextRetryDate: Date? = nil) {
        self.attemptCount = max(0, attemptCount)
        self.mode = mode
        self.nextRetryDate = nextRetryDate
    }
}

public enum UpdateRetryPhase: Equatable, Sendable {
    case inactive
    case waitingForConnectivity
    case scheduled(Date)
    case checking
}

public enum UpdateRetryEffect: Equatable, Sendable {
    case none
    case performRetry
    case exhausted
}

/// Pure state machine for recovery after a scheduled update check fails due to
/// transient networking. The app supplies clock, connectivity, persistence,
/// timers, and the actual update-check closure.
public struct UpdateRetryCoordinator: Equatable, Sendable {
    public static let reconnectDebounce: TimeInterval = 30
    public static let busyRetryDelay: TimeInterval = 60
    public static let backoffDelays: [TimeInterval] = [5 * 60, 15 * 60, 60 * 60]

    public private(set) var snapshot: UpdateRetrySnapshot?

    public init(snapshot: UpdateRetrySnapshot? = nil) {
        guard let snapshot,
              snapshot.attemptCount >= 0,
              snapshot.attemptCount <= Self.backoffDelays.count
        else {
            self.snapshot = nil
            return
        }
        self.snapshot = snapshot
    }

    public var phase: UpdateRetryPhase {
        guard let snapshot else { return .inactive }
        switch snapshot.mode {
        case .waitingForConnectivity:
            return .waitingForConnectivity
        case .scheduled:
            guard let nextRetryDate = snapshot.nextRetryDate else {
                return .waitingForConnectivity
            }
            return .scheduled(nextRetryDate)
        case .checking:
            return .checking
        }
    }

    /// Restores a pending episode after launch. A check interrupted by process
    /// termination is retried after the same reconnect debounce as an overdue
    /// timer, rather than firing during launch setup.
    @discardableResult
    public mutating func resume(
        now: Date,
        connectivityAvailable: Bool,
        automaticallyChecks: Bool
    ) -> UpdateRetryEffect {
        guard automaticallyChecks else {
            snapshot = nil
            return .none
        }
        guard var snapshot else { return .none }

        guard connectivityAvailable else {
            snapshot.mode = .waitingForConnectivity
            snapshot.nextRetryDate = nil
            self.snapshot = snapshot
            return .none
        }

        switch snapshot.mode {
        case .waitingForConnectivity, .checking:
            snapshot.mode = .scheduled
            snapshot.nextRetryDate = now.addingTimeInterval(Self.reconnectDebounce)
        case .scheduled:
            if snapshot.nextRetryDate == nil || snapshot.nextRetryDate! <= now {
                snapshot.nextRetryDate = now.addingTimeInterval(Self.reconnectDebounce)
            }
        }
        self.snapshot = snapshot
        return .none
    }

    /// Starts or advances a recovery episode after a background check fails.
    @discardableResult
    public mutating func recordNetworkFailure(
        now: Date,
        connectivityAvailable: Bool
    ) -> UpdateRetryEffect {
        var snapshot = snapshot ?? UpdateRetrySnapshot(
            attemptCount: 0,
            mode: .waitingForConnectivity
        )

        guard snapshot.attemptCount < Self.backoffDelays.count else {
            self.snapshot = nil
            return .exhausted
        }

        if connectivityAvailable {
            let delay = Self.backoffDelays[snapshot.attemptCount]
            snapshot.mode = .scheduled
            snapshot.nextRetryDate = now.addingTimeInterval(delay)
        } else {
            snapshot.mode = .waitingForConnectivity
            snapshot.nextRetryDate = nil
        }
        self.snapshot = snapshot
        return .none
    }

    /// Debounces a real reconnect and pauses an unstarted timer when the path
    /// drops again. A check already in flight owns its own completion event.
    @discardableResult
    public mutating func connectivityChanged(
        available: Bool,
        now: Date
    ) -> UpdateRetryEffect {
        guard var snapshot else { return .none }
        if available {
            guard snapshot.mode == .waitingForConnectivity else { return .none }
            snapshot.mode = .scheduled
            snapshot.nextRetryDate = now.addingTimeInterval(Self.reconnectDebounce)
        } else {
            guard snapshot.mode == .scheduled else { return .none }
            snapshot.mode = .waitingForConnectivity
            snapshot.nextRetryDate = nil
        }
        self.snapshot = snapshot
        return .none
    }

    /// Claims a due retry exactly once. If Sparkle is busy, preserve the
    /// attempt and move the timer by a minute instead of overlapping sessions.
    @discardableResult
    public mutating func retryTimerFired(
        now: Date,
        updaterCanCheck: Bool
    ) -> UpdateRetryEffect {
        guard var snapshot,
              snapshot.mode == .scheduled,
              let nextRetryDate = snapshot.nextRetryDate,
              nextRetryDate <= now
        else { return .none }

        guard updaterCanCheck else {
            snapshot.nextRetryDate = now.addingTimeInterval(Self.busyRetryDelay)
            self.snapshot = snapshot
            return .none
        }

        guard snapshot.attemptCount < Self.backoffDelays.count else {
            self.snapshot = nil
            return .exhausted
        }
        snapshot.attemptCount += 1
        snapshot.mode = .checking
        snapshot.nextRetryDate = nil
        self.snapshot = snapshot
        return .performRetry
    }

    public mutating func clear() {
        snapshot = nil
    }
}
