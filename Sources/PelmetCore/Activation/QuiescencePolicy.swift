import Foundation

/// Decides when the executor may discharge its post-activation obligations
/// (restore drag, focus give-back, auto-rehide re-arm) without fighting the
/// user. Pure so the rules are unit-testable: the executor samples the
/// world every poll and feeds the facts in.
public enum QuiescencePolicy {

    public enum Decision: Equatable {
        /// Something is (or may be) in the user's hands — poll again.
        case wait
        /// The coast is clear: restore the bar, give focus back, re-arm.
        case proceed
        /// Hard cap hit — discharge NOTHING (never drag or refocus under a
        /// still-open menu); just release state so rehide can re-arm.
        case giveUp
    }

    /// Act only this long AFTER the user's last input — the restore drag
    /// must never hijack the cursor the instant a menu entry is picked.
    public static let idleGrace: TimeInterval = 1.0
    /// Consecutive "no menu open" polls required — submenu churn replaces
    /// menu windows, so single observations flicker.
    public static let requiredClosedPolls = 2
    public static let hardCap: TimeInterval = 90

    public static func decide(
        menusOpen: Bool,
        closedStreak: Int,
        buttonsDown: Bool,
        secondsSinceLastInput: TimeInterval,
        elapsed: TimeInterval
    ) -> Decision {
        if elapsed >= hardCap { return .giveUp }
        if menusOpen { return .wait }
        if closedStreak < requiredClosedPolls { return .wait }
        if buttonsDown || secondsSinceLastInput < idleGrace { return .wait }
        return .proceed
    }
}
