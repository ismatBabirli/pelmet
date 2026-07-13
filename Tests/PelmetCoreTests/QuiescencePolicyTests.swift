import Testing
@testable import PelmetCore

struct QuiescencePolicyTests {

    private func decide(
        menusOpen: Bool = false,
        closedStreak: Int = QuiescencePolicy.requiredClosedPolls,
        buttonsDown: Bool = false,
        secondsSinceLastInput: Double = QuiescencePolicy.idleGrace,
        elapsed: Double = 5
    ) -> QuiescencePolicy.Decision {
        QuiescencePolicy.decide(
            menusOpen: menusOpen,
            closedStreak: closedStreak,
            buttonsDown: buttonsDown,
            secondsSinceLastInput: secondsSinceLastInput,
            elapsed: elapsed
        )
    }

    @Test func testOpenMenuWaits() {
        #expect(decide(menusOpen: true, closedStreak: 0) == .wait)
    }

    @Test func testSingleClosedObservationWaits() {
        // Submenu window churn: one "closed" poll isn't proof.
        #expect(decide(closedStreak: 1) == .wait)
    }

    @Test func testClosedStreakWithIdleUserProceeds() {
        #expect(decide() == .proceed)
    }

    @Test func testPressedButtonWaits() {
        #expect(decide(buttonsDown: true) == .wait)
    }

    @Test func testRecentInputWaits() {
        // The user just clicked a menu entry — don't hijack the cursor yet.
        #expect(decide(secondsSinceLastInput: 0.4) == .wait)
    }

    @Test func testIdleGraceBoundaryProceeds() {
        #expect(decide(secondsSinceLastInput: QuiescencePolicy.idleGrace) == .proceed)
    }

    @Test func testHardCapGivesUpEvenWithMenuOpen() {
        #expect(decide(menusOpen: true, closedStreak: 0, elapsed: QuiescencePolicy.hardCap) == .giveUp)
    }

    @Test func testJustUnderTheCapStillWaits() {
        #expect(decide(menusOpen: true, closedStreak: 0, elapsed: QuiescencePolicy.hardCap - 1) == .wait)
    }
}
