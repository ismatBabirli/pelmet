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
        #expect(session.handle(.stepCompleted) == [.startVerification(deadline: 0.7, persistence: nil)])
        #expect(session.handle(.verified(.menuOpened)) == [.finish(.activated(.menuOpened))])
        // Finished: further events are ignored.
        #expect(session.handle(.verificationTimedOut).isEmpty)
    }

    @Test func testTimeoutCascadesThroughTheChain() {
        var session = ActivationSession(strategies: fullChain(), targetWasSwallowed: true)
        _ = session.handle(.begin)
        _ = session.handle(.stepCompleted)                          // click posted
        // Every post-click step is gated on "did that click open a menu?"
        #expect(session.handle(.verificationTimedOut) == [.checkMenuOpen])
        #expect(session.handle(.menuCheck(open: false)) == [.perform(.axPress)])
        #expect(session.handle(.stepCompleted) == [
            .startVerification(deadline: 1.2, persistence: 1.1),
        ])
        #expect(session.handle(.verificationTimedOut) == [.checkMenuOpen])
        #expect(session.handle(.menuCheck(open: false)) == [.perform(.appMenuClearance)])
        #expect(session.handle(.stepCompleted) == [.checkMenuOpen])
        #expect(session.handle(.menuCheck(open: false)) == [.perform(.dragToExpose(dragPlan))])
        #expect(session.handle(.stepCompleted) == [.checkMenuOpen])
        #expect(session.handle(.menuCheck(open: false)) == [.perform(.clickTargetAfterReflow)])
        #expect(session.handle(.stepCompleted) == [.startVerification(deadline: 0.7, persistence: nil)])
        // Reflow click verified: menu opened, restore is owed.
        #expect(session.handle(.verified(.menuOpened)) == [
            .restoreDrag(dragPlan), .finish(.activated(.menuOpened)),
        ])
    }

    @Test func testUnverifiedReflowClickIsSoftSuccess() {
        var session = ActivationSession(strategies: fullChain(), targetWasSwallowed: true)
        _ = session.handle(.begin)
        _ = session.handle(.stepCompleted)
        _ = session.handle(.verificationTimedOut)
        _ = session.handle(.menuCheck(open: false))     // → axPress
        _ = session.handle(.stepCompleted)
        _ = session.handle(.verificationTimedOut)
        _ = session.handle(.menuCheck(open: false))     // → clearance
        _ = session.handle(.stepCompleted)
        _ = session.handle(.menuCheck(open: false))     // → drag
        _ = session.handle(.stepCompleted)
        _ = session.handle(.menuCheck(open: false))     // → reflow click
        _ = session.handle(.stepCompleted)              // → verification
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
        _ = session.handle(.verificationTimedOut)
        _ = session.handle(.menuCheck(open: false))     // → axPress
        _ = session.handle(.stepCompleted)
        // Exhausted → single retry of the first click, gated like any
        // other post-click step.
        #expect(session.handle(.verificationTimedOut) == [.checkMenuOpen])
        #expect(session.handle(.menuCheck(open: false)) == [.perform(click)])
        _ = session.handle(.stepCompleted)
        // Second exhaustion: no second retry. Swallowed target, no reflow
        // click → honest failure.
        #expect(session.handle(.verificationTimedOut) == [.finish(.failed(.noRoomToExpose))])
    }

    @Test func testUnverifiedVisibleTargetIsSoftSuccess() {
        var session = ActivationSession(strategies: [click], targetWasSwallowed: false)
        _ = session.handle(.begin)
        _ = session.handle(.stepCompleted)
        #expect(session.handle(.verificationTimedOut) == [.checkMenuOpen])
        #expect(session.handle(.menuCheck(open: false)) == [.perform(click)]) // the one retry
        _ = session.handle(.stepCompleted)
        #expect(session.handle(.verificationTimedOut) == [.finish(.activated(.unverified))])
    }

    @Test func testAbortMidDragReleasesButtonsAndRestores() {
        var session = ActivationSession(strategies: fullChain(), targetWasSwallowed: true)
        _ = session.handle(.begin)
        _ = session.handle(.stepCompleted)
        _ = session.handle(.verificationTimedOut)
        _ = session.handle(.menuCheck(open: false))
        _ = session.handle(.stepCompleted)
        _ = session.handle(.verificationTimedOut)
        _ = session.handle(.menuCheck(open: false))
        _ = session.handle(.stepCompleted)              // clearance done
        _ = session.handle(.menuCheck(open: false))     // → drag
        _ = session.handle(.stepCompleted)              // drag completed
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
        _ = session.handle(.menuCheck(open: false))
        _ = session.handle(.stepCompleted)
        _ = session.handle(.verificationTimedOut)
        _ = session.handle(.menuCheck(open: false))
        _ = session.handle(.stepCompleted)              // clearance done
        _ = session.handle(.menuCheck(open: false))     // → drag
        #expect(session.handle(.stepFailed) == [.finish(.failed(.noRoomToExpose))])
    }

    @Test func testFailedAXPressAdvancesToTheNextStrategy() {
        var session = ActivationSession(strategies: fullChain(), targetWasSwallowed: true)
        _ = session.handle(.begin)
        _ = session.handle(.stepCompleted)
        _ = session.handle(.verificationTimedOut)
        _ = session.handle(.menuCheck(open: false))     // → axPress
        #expect(session.handle(.stepFailed) == [.checkMenuOpen])
        #expect(session.handle(.menuCheck(open: false)) == [.perform(.appMenuClearance)])
    }

    @Test func testEmptyPlanFailsImmediately() {
        var session = ActivationSession(strategies: [], targetWasSwallowed: false)
        #expect(session.handle(.begin) == [.finish(.failed(.itemVanished))])
    }

    // MARK: - Menu gate

    @Test func testMenuGateOpenBeforeAXPressFinishesWithoutTouchingIt() {
        var session = ActivationSession(strategies: fullChain(), targetWasSwallowed: true)
        _ = session.handle(.begin)
        _ = session.handle(.stepCompleted)
        _ = session.handle(.verificationTimedOut)
        // Verification missed the menu but the gate sees it: success, no
        // AXPress toggle-close, no clearance, no drag.
        #expect(session.handle(.menuCheck(open: true)) == [.finish(.activated(.menuOpened))])
        #expect(session.handle(.stepCompleted).isEmpty)
    }

    @Test func testMenuGateOpenAfterDragOwesRestore() {
        var session = ActivationSession(strategies: fullChain(), targetWasSwallowed: true)
        _ = session.handle(.begin)
        _ = session.handle(.stepCompleted)
        _ = session.handle(.verificationTimedOut)
        _ = session.handle(.menuCheck(open: false))
        _ = session.handle(.stepCompleted)
        _ = session.handle(.verificationTimedOut)
        _ = session.handle(.menuCheck(open: false))
        _ = session.handle(.stepCompleted)              // clearance done
        _ = session.handle(.menuCheck(open: false))     // → drag
        _ = session.handle(.stepCompleted)              // drag completed
        #expect(session.handle(.menuCheck(open: true)) == [
            .restoreDrag(dragPlan), .finish(.activated(.menuOpened)),
        ])
    }

    @Test func testMenuGateGuardsTheRetry() {
        var session = ActivationSession(strategies: [click], targetWasSwallowed: false)
        _ = session.handle(.begin)
        _ = session.handle(.stepCompleted)
        #expect(session.handle(.verificationTimedOut) == [.checkMenuOpen])
        // The menu the first click opened is found before the retry can
        // toggle it closed.
        #expect(session.handle(.menuCheck(open: true)) == [.finish(.activated(.menuOpened))])
    }

    @Test func testNoGateWhenNoClickWasPosted() {
        var session = ActivationSession(strategies: fullChain(), targetWasSwallowed: true)
        _ = session.handle(.begin)
        // The click could not even be posted — nothing can be open yet.
        #expect(session.handle(.stepFailed) == [.perform(.axPress)])
    }

    @Test func testSpuriousMenuCheckIsIgnored() {
        var session = ActivationSession(strategies: fullChain(), targetWasSwallowed: true)
        _ = session.handle(.begin)
        #expect(session.handle(.menuCheck(open: true)).isEmpty)
    }

    @Test func testAbortWhileAwaitingGateReleasesButtons() {
        var session = ActivationSession(strategies: [click, .axPress], targetWasSwallowed: true)
        _ = session.handle(.begin)
        _ = session.handle(.stepCompleted)
        _ = session.handle(.verificationTimedOut)       // → checkMenuOpen pending
        #expect(session.handle(.aborted(.interrupted)) == [
            .releaseMouseButtons, .finish(.failed(.interrupted)),
        ])
    }
}
