import Testing
@testable import PelmetCore

struct OnboardingCheckPlanTests {

    @Test func testCollapsedUpgradeWithoutClassificationStillAttemptsTelemetryNotice() {
        let plan = OnboardingCheckPlan(
            isCollapsed: true,
            hasClassification: false,
            toggleVisible: true
        )

        #expect(plan.attemptTelemetryNotice)
        #expect(!plan.attemptLaunchTips)
        #expect(!plan.attemptLayoutEducation)
        #expect(!plan.attemptOneClickOffer)
    }

    @Test func testInvisibleToggleDefersEveryToggleAnchoredCheck() {
        let plan = OnboardingCheckPlan(
            isCollapsed: true,
            hasClassification: true,
            toggleVisible: false
        )

        #expect(!plan.attemptTelemetryNotice)
        #expect(!plan.attemptOneClickOffer)
    }

    @Test func testExpandedOnboardingSequenceIsPreserved() {
        let plan = OnboardingCheckPlan(
            isCollapsed: false,
            hasClassification: true,
            toggleVisible: true
        )

        #expect(plan.attemptLaunchTips)
        #expect(plan.attemptLayoutEducation)
        #expect(plan.attemptTelemetryNotice)
        #expect(plan.attemptOneClickOffer)
    }

    @Test func testTelemetryUpgradeArmsFallbackAfterWelcomeCompleted() {
        #expect(OnboardingCheckPlan.shouldArmFallback(
            welcomeTipShown: true,
            telemetryNoticeNeeded: true
        ))
        #expect(OnboardingCheckPlan.shouldArmFallback(
            welcomeTipShown: false,
            telemetryNoticeNeeded: false
        ))
        #expect(!OnboardingCheckPlan.shouldArmFallback(
            welcomeTipShown: true,
            telemetryNoticeNeeded: false
        ))
    }
}
