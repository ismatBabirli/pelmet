import Testing
@testable import PelmetCore
import CoreGraphics

struct ActivationSessionTests {

    private let click = ActivationStrategy.syntheticClick(at: CGPoint(x: 720, y: 965))
    private let dragPlan = DragPlan(
        neighborFrame: CGRect(x: 900, y: 949, width: 40, height: 33),
        from: CGPoint(x: 920, y: 965),
        to: CGPoint(x: 635, y: 965)
    )

    private func fullChain() -> [ActivationStrategy] {
        [click, .axPress, .appMenuClearance, .dragToExpose(dragPlan), .clickTargetAfterReflow]
    }

    @Test func testVerifiedFirstClickShortCircuits() {
        var session = ActivationSession(strategies: fullChain(), targetWasSwallowed: true)
        #expect(session.handle(.begin) == [.perform(click)])
        #expect(session.handle(.stepCompleted) == [.startVerification(deadline: 0.7)])
        #expect(session.handle(.verified(.menuOpened)) == [.finish(.activated(.menuOpened))])
        // Finished: further events are ignored.
        #expect(session.handle(.verificationTimedOut).isEmpty)
    }

    @Test func testTimeoutCascadesThroughTheChain() {
        var session = ActivationSession(strategies: fullChain(), targetWasSwallowed: true)
        _ = session.handle(.begin)
        _ = session.handle(.stepCompleted)                          // click posted
        #expect(session.handle(.verificationTimedOut) == [.perform(.axPress)])
        #expect(session.handle(.stepCompleted) == [.startVerification(deadline: 1.2)])
        #expect(session.handle(.verificationTimedOut) == [.perform(.appMenuClearance)])
        #expect(session.handle(.stepCompleted) == [.perform(.dragToExpose(dragPlan))])
        #expect(session.handle(.stepCompleted) == [.perform(.clickTargetAfterReflow)])
        #expect(session.handle(.stepCompleted) == [.startVerification(deadline: 0.7)])
        // Reflow click verified: menu opened, restore is owed.
        #expect(session.handle(.verified(.menuOpened)) == [
            .restoreDrag(dragPlan), .finish(.activated(.menuOpened)),
        ])
    }

    @Test func testUnverifiedReflowClickIsSoftSuccess() {
        var session = ActivationSession(strategies: fullChain(), targetWasSwallowed: true)
        _ = session.handle(.begin)
        _ = session.handle(.stepCompleted)
        _ = session.handle(.verificationTimedOut)   // → axPress
        _ = session.handle(.stepCompleted)
        _ = session.handle(.verificationTimedOut)   // → clearance
        _ = session.handle(.stepCompleted)          // → drag
        _ = session.handle(.stepCompleted)          // → reflow click
        _ = session.handle(.stepCompleted)          // → verification
        // Timed out after the final click, but a drag happened: no retry,
        // soft success, restore owed.
        #expect(session.handle(.verificationTimedOut) == [
            .restoreDrag(dragPlan), .finish(.activated(.unverified)),
        ])
    }

    @Test func testExactlyOneRetryWhenNoDragHappened() {
        var session = ActivationSession(
            strategies: [click, .axPress], targetWasSwallowed: true
        )
        _ = session.handle(.begin)
        _ = session.handle(.stepCompleted)
        _ = session.handle(.verificationTimedOut)   // → axPress
        _ = session.handle(.stepCompleted)
        // Exhausted → single retry of the first click.
        #expect(session.handle(.verificationTimedOut) == [.perform(click)])
        _ = session.handle(.stepCompleted)
        // Second exhaustion: no second retry. Swallowed target, no reflow
        // click → honest failure.
        #expect(session.handle(.verificationTimedOut) == [.finish(.failed(.noRoomToExpose))])
    }

    @Test func testUnverifiedVisibleTargetIsSoftSuccess() {
        var session = ActivationSession(strategies: [click], targetWasSwallowed: false)
        _ = session.handle(.begin)
        _ = session.handle(.stepCompleted)
        #expect(session.handle(.verificationTimedOut) == [.perform(click)]) // the one retry
        _ = session.handle(.stepCompleted)
        #expect(session.handle(.verificationTimedOut) == [.finish(.activated(.unverified))])
    }

    @Test func testAbortMidDragReleasesButtonsAndRestores() {
        var session = ActivationSession(strategies: fullChain(), targetWasSwallowed: true)
        _ = session.handle(.begin)
        _ = session.handle(.stepCompleted)
        _ = session.handle(.verificationTimedOut)
        _ = session.handle(.stepCompleted)
        _ = session.handle(.verificationTimedOut)
        _ = session.handle(.stepCompleted)          // clearance done → drag next
        _ = session.handle(.stepCompleted)          // drag completed
        let effects = session.handle(.aborted(.interrupted))
        #expect(effects == [
            .releaseMouseButtons,
            .restoreDrag(dragPlan),
            .finish(.failed(.interrupted)),
        ])
    }

    @Test func testAbortBeforeAnythingReleasesButtonsOnly() {
        var session = ActivationSession(strategies: [click], targetWasSwallowed: false)
        _ = session.handle(.begin)
        #expect(session.handle(.aborted(.userInteracting)) == [
            .releaseMouseButtons, .finish(.failed(.userInteracting)),
        ])
    }

    @Test func testFailedDragEndsTheSessionWithoutReflowClick() {
        var session = ActivationSession(strategies: fullChain(), targetWasSwallowed: true)
        _ = session.handle(.begin)
        _ = session.handle(.stepCompleted)
        _ = session.handle(.verificationTimedOut)
        _ = session.handle(.stepCompleted)
        _ = session.handle(.verificationTimedOut)
        _ = session.handle(.stepCompleted)          // clearance → drag next
        #expect(session.handle(.stepFailed) == [.finish(.failed(.noRoomToExpose))])
    }

    @Test func testFailedAXPressAdvancesToTheNextStrategy() {
        var session = ActivationSession(strategies: fullChain(), targetWasSwallowed: true)
        _ = session.handle(.begin)
        _ = session.handle(.stepCompleted)
        _ = session.handle(.verificationTimedOut)   // → axPress
        #expect(session.handle(.stepFailed) == [.perform(.appMenuClearance)])
    }

    @Test func testEmptyPlanFailsImmediately() {
        var session = ActivationSession(strategies: [], targetWasSwallowed: false)
        #expect(session.handle(.begin) == [.finish(.failed(.itemVanished))])
    }
}
