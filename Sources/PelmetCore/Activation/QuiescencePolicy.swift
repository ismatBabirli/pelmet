import Foundation

/// Decides when the executor may release its auto-rehide hold after a
/// pointer-free Accessibility action. Pure so the rules are unit-testable:
/// the executor samples the world every poll and feeds the facts in.
public enum QuiescencePolicy {

    public enum Decision: Equatable {
        /// Something is (or may be) in the user's hands — poll again.
        case wait
        /// The coast is clear: release the hold and re-arm auto-rehide.
        case proceed
        /// Hard cap hit — release the observation state so rehide can re-arm.
        case giveUp
    }

    /// Wait this long after the user's last input before re-arming auto-rehide.
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
