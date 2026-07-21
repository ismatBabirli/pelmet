/// Describes which one-time onboarding checks the AppKit layer should attempt
/// for its current menu bar state. The individual presenters still own their
/// persisted one-shot gates; this plan only keeps UI state from starving a
/// presenter that is safe to run.
public struct OnboardingCheckPlan: Equatable {

    public let attemptLaunchTips: Bool
    public let attemptLayoutEducation: Bool
    public let attemptTelemetryNotice: Bool
    public let attemptOneClickOffer: Bool

    public init(isCollapsed: Bool, hasClassification: Bool, toggleVisible: Bool) {
        attemptLaunchTips = !isCollapsed
        attemptLayoutEducation = !isCollapsed && hasClassification && toggleVisible

        // The privacy notice anchors to the always-visible toggle and must not
        // depend on the managed icons being expanded. Existing users commonly
        // upgrade while Pelmet is collapsed.
        attemptTelemetryNotice = toggleVisible

        // Keep the optional feature pitch in the expanded onboarding sequence.
        attemptOneClickOffer = !isCollapsed && toggleVisible
    }

    /// A confirmed layout normally drives onboarding. The fallback is also
    /// required when an existing user has completed the welcome but still needs
    /// a newly introduced privacy notice.
    public static func shouldArmFallback(
        welcomeTipShown: Bool,
        telemetryNoticeNeeded: Bool
    ) -> Bool {
        !welcomeTipShown || telemetryNoticeNeeded
    }
}
