import Foundation
import Testing
@testable import PelmetCore

struct SupportNudgePolicyTests {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func notShownUntilStarNudgeHasFinishedAndGracePeriodElapses() {
        let now = base.addingTimeInterval(SupportNudgePolicy.initialDelay * 10)

        #expect(SupportNudgePolicy.shouldShow(
            firstLaunchAt: base,
            hasManagedItems: true,
            starNudgeDismissed: false,
            starNudgeLastShownAt: base,
            dismissedPermanently: false,
            lastShownAt: nil,
            showCount: 0,
            now: now
        ) == false)

        let afterStarGrace = base.addingTimeInterval(SupportNudgePolicy.graceAfterStarNudge)
        #expect(SupportNudgePolicy.shouldShow(
            firstLaunchAt: base,
            hasManagedItems: true,
            starNudgeDismissed: true,
            starNudgeLastShownAt: base,
            dismissedPermanently: false,
            lastShownAt: nil,
            showCount: 0,
            now: afterStarGrace
        ))
    }

    @Test func notShownWithoutEngagement() {
        let now = base.addingTimeInterval(SupportNudgePolicy.initialDelay * 10)
        #expect(SupportNudgePolicy.shouldShow(
            firstLaunchAt: base,
            hasManagedItems: false,
            starNudgeDismissed: true,
            starNudgeLastShownAt: base,
            dismissedPermanently: false,
            lastShownAt: nil,
            showCount: 0,
            now: now
        ) == false)
    }

    @Test func notShownWhenStarTimestampIsMissing() {
        let now = base.addingTimeInterval(SupportNudgePolicy.initialDelay * 10)
        #expect(SupportNudgePolicy.shouldShow(
            firstLaunchAt: base,
            hasManagedItems: true,
            starNudgeDismissed: true,
            starNudgeLastShownAt: nil,
            dismissedPermanently: false,
            lastShownAt: nil,
            showCount: 0,
            now: now
        ) == false)
    }

    @Test func remindersWaitThirtyDays() {
        let starFinishedAt = base.addingTimeInterval(SupportNudgePolicy.graceAfterStarNudge)
        let shownAt = starFinishedAt.addingTimeInterval(SupportNudgePolicy.initialDelay)
        let tooSoon = shownAt.addingTimeInterval(SupportNudgePolicy.reminderInterval - 1)

        #expect(SupportNudgePolicy.shouldShow(
            firstLaunchAt: base,
            hasManagedItems: true,
            starNudgeDismissed: true,
            starNudgeLastShownAt: base,
            dismissedPermanently: false,
            lastShownAt: shownAt,
            showCount: 1,
            now: tooSoon
        ) == false)

        let due = shownAt.addingTimeInterval(SupportNudgePolicy.reminderInterval)
        #expect(SupportNudgePolicy.shouldShow(
            firstLaunchAt: base,
            hasManagedItems: true,
            starNudgeDismissed: true,
            starNudgeLastShownAt: base,
            dismissedPermanently: false,
            lastShownAt: shownAt,
            showCount: 1,
            now: due
        ))
    }

    @Test func notShownOnceCapReachedOrDismissed() {
        let now = base.addingTimeInterval(SupportNudgePolicy.reminderInterval * 100)

        #expect(SupportNudgePolicy.shouldShow(
            firstLaunchAt: base,
            hasManagedItems: true,
            starNudgeDismissed: true,
            starNudgeLastShownAt: base,
            dismissedPermanently: false,
            lastShownAt: base,
            showCount: SupportNudgePolicy.maxShows,
            now: now
        ) == false)

        #expect(SupportNudgePolicy.shouldShow(
            firstLaunchAt: base,
            hasManagedItems: true,
            starNudgeDismissed: true,
            starNudgeLastShownAt: base,
            dismissedPermanently: true,
            lastShownAt: nil,
            showCount: 0,
            now: now
        ) == false)
    }
}
