import Foundation
import Testing
@testable import PelmetCore

struct StarNudgePolicyTests {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func notShownBeforeInitialDelay() {
        let now = base.addingTimeInterval(StarNudgePolicy.initialDelay - 1)
        #expect(StarNudgePolicy.shouldShow(
            firstLaunchAt: base,
            hasManagedItems: true,
            dismissedPermanently: false,
            lastShownAt: nil,
            showCount: 0,
            now: now
        ) == false)
    }

    @Test func shownAtInitialDelayWhenEngaged() {
        let now = base.addingTimeInterval(StarNudgePolicy.initialDelay)
        #expect(StarNudgePolicy.shouldShow(
            firstLaunchAt: base,
            hasManagedItems: true,
            dismissedPermanently: false,
            lastShownAt: nil,
            showCount: 0,
            now: now
        ))
    }

    @Test func notShownWithoutEngagement() {
        let now = base.addingTimeInterval(StarNudgePolicy.initialDelay * 10)
        #expect(StarNudgePolicy.shouldShow(
            firstLaunchAt: base,
            hasManagedItems: false,
            dismissedPermanently: false,
            lastShownAt: nil,
            showCount: 0,
            now: now
        ) == false)
    }

    @Test func notShownWhenDismissedPermanently() {
        let now = base.addingTimeInterval(StarNudgePolicy.initialDelay * 10)
        #expect(StarNudgePolicy.shouldShow(
            firstLaunchAt: base,
            hasManagedItems: true,
            dismissedPermanently: true,
            lastShownAt: nil,
            showCount: 0,
            now: now
        ) == false)
    }

    @Test func notShownWhenFirstLaunchUnknown() {
        let now = base.addingTimeInterval(StarNudgePolicy.initialDelay * 10)
        #expect(StarNudgePolicy.shouldShow(
            firstLaunchAt: nil,
            hasManagedItems: true,
            dismissedPermanently: false,
            lastShownAt: nil,
            showCount: 0,
            now: now
        ) == false)
    }

    @Test func snoozedUntilReminderIntervalElapses() {
        let shownAt = base.addingTimeInterval(StarNudgePolicy.initialDelay)
        let tooSoon = shownAt.addingTimeInterval(StarNudgePolicy.reminderInterval - 1)
        #expect(StarNudgePolicy.shouldShow(
            firstLaunchAt: base,
            hasManagedItems: true,
            dismissedPermanently: false,
            lastShownAt: shownAt,
            showCount: 1,
            now: tooSoon
        ) == false)

        let due = shownAt.addingTimeInterval(StarNudgePolicy.reminderInterval)
        #expect(StarNudgePolicy.shouldShow(
            firstLaunchAt: base,
            hasManagedItems: true,
            dismissedPermanently: false,
            lastShownAt: shownAt,
            showCount: 1,
            now: due
        ))
    }

    @Test func notShownOnceCapReached() {
        let shownAt = base
        let wayLater = base.addingTimeInterval(StarNudgePolicy.reminderInterval * 100)
        #expect(StarNudgePolicy.shouldShow(
            firstLaunchAt: base,
            hasManagedItems: true,
            dismissedPermanently: false,
            lastShownAt: shownAt,
            showCount: StarNudgePolicy.maxShows,
            now: wayLater
        ) == false)
    }

    @Test func reminderNeedsAPriorShowTimestamp() {
        // showCount > 0 but no lastShownAt is inconsistent state: never show.
        let now = base.addingTimeInterval(StarNudgePolicy.reminderInterval * 10)
        #expect(StarNudgePolicy.shouldShow(
            firstLaunchAt: base,
            hasManagedItems: true,
            dismissedPermanently: false,
            lastShownAt: nil,
            showCount: 1,
            now: now
        ) == false)
    }
}
