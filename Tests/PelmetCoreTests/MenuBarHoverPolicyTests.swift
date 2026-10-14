import CoreGraphics
import Testing
@testable import PelmetCore

struct MenuBarHoverPolicyTests {

    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let toggle = CGRect(x: 1430, y: 949, width: 32, height: 33)

    @Test func testBandUsesFullScreenWidthAndToggleHeight() {
        let band = MenuBarHoverRegion.band(toggleFrame: toggle, screenFrame: screen)

        #expect(band == CGRect(x: 0, y: 949, width: 1512, height: 33))
        #expect(MenuBarHoverRegion.contains(
            CGPoint(x: 20, y: 960),
            toggleFrame: toggle,
            screenFrame: screen
        ))
        #expect(MenuBarHoverRegion.contains(
            CGPoint(x: 750, y: 960),
            toggleFrame: toggle,
            screenFrame: screen
        ))
    }

    @Test func testBandBoundariesExcludePointsOutsideTheMenuBar() {
        #expect(MenuBarHoverRegion.contains(
            CGPoint(x: 0, y: 949),
            toggleFrame: toggle,
            screenFrame: screen
        ))
        #expect(!MenuBarHoverRegion.contains(
            CGPoint(x: 0, y: 948.9),
            toggleFrame: toggle,
            screenFrame: screen
        ))
        #expect(!MenuBarHoverRegion.contains(
            CGPoint(x: 1512, y: 960),
            toggleFrame: toggle,
            screenFrame: screen
        ))
        #expect(!MenuBarHoverRegion.contains(
            CGPoint(x: 400, y: 982),
            toggleFrame: toggle,
            screenFrame: screen
        ))
    }

    @Test func testNotchDoesNotCreateAHoleInTheTriggerBand() {
        #expect(MenuBarHoverRegion.contains(
            CGPoint(x: 755, y: 960),
            toggleFrame: toggle,
            screenFrame: screen
        ))
    }

    @Test func testNegativeCoordinateDisplayIsHandled() {
        let secondary = CGRect(x: -1920, y: 120, width: 1920, height: 1080)
        let secondaryToggle = CGRect(x: -60, y: 1176, width: 32, height: 24)

        #expect(MenuBarHoverRegion.band(
            toggleFrame: secondaryToggle,
            screenFrame: secondary
        ) == CGRect(x: -1920, y: 1176, width: 1920, height: 24))
        #expect(MenuBarHoverRegion.contains(
            CGPoint(x: -1800, y: 1185),
            toggleFrame: secondaryToggle,
            screenFrame: secondary
        ))
        #expect(!MenuBarHoverRegion.contains(
            CGPoint(x: 200, y: 1185),
            toggleFrame: secondaryToggle,
            screenFrame: secondary
        ))
    }

    @Test func testMissingInvalidOrOffscreenFramesHaveNoRegion() {
        #expect(MenuBarHoverRegion.band(toggleFrame: nil, screenFrame: screen) == nil)
        #expect(MenuBarHoverRegion.band(toggleFrame: toggle, screenFrame: nil) == nil)
        #expect(MenuBarHoverRegion.band(
            toggleFrame: .zero,
            screenFrame: screen
        ) == nil)
        #expect(MenuBarHoverRegion.band(
            toggleFrame: CGRect(x: 1430, y: 1100, width: 32, height: 24),
            screenFrame: screen
        ) == nil)
    }

    @Test func testTrackerEmitsOnlyEdgeTransitions() {
        var tracker = MenuBarHoverTracker()
        let inside = CGPoint(x: 500, y: 960)
        let outside = CGPoint(x: 500, y: 900)

        #expect(tracker.update(
            enabled: true,
            buttonsDown: false,
            point: outside,
            toggleFrame: toggle,
            screenFrame: screen
        ) == nil)
        #expect(tracker.update(
            enabled: true,
            buttonsDown: false,
            point: inside,
            toggleFrame: toggle,
            screenFrame: screen
        ) == .entered)
        #expect(tracker.update(
            enabled: true,
            buttonsDown: false,
            point: inside,
            toggleFrame: toggle,
            screenFrame: screen
        ) == nil)
        #expect(tracker.update(
            enabled: true,
            buttonsDown: false,
            point: outside,
            toggleFrame: toggle,
            screenFrame: screen
        ) == .exited)
    }

    @Test func testTrackerIgnoresDragUntilButtonsAreReleased() {
        var tracker = MenuBarHoverTracker()
        let inside = CGPoint(x: 500, y: 960)

        #expect(tracker.update(
            enabled: true,
            buttonsDown: true,
            point: inside,
            toggleFrame: toggle,
            screenFrame: screen
        ) == nil)
        #expect(!tracker.isPointerInside)
        #expect(tracker.update(
            enabled: true,
            buttonsDown: false,
            point: inside,
            toggleFrame: toggle,
            screenFrame: screen
        ) == .entered)
    }

    @Test func testDisablingResetsTrackerWithoutExitSideEffects() {
        var tracker = MenuBarHoverTracker()
        let inside = CGPoint(x: 500, y: 960)

        #expect(tracker.update(
            enabled: true,
            buttonsDown: false,
            point: inside,
            toggleFrame: toggle,
            screenFrame: screen
        ) == .entered)
        #expect(tracker.update(
            enabled: false,
            buttonsDown: false,
            point: inside,
            toggleFrame: toggle,
            screenFrame: screen
        ) == nil)
        #expect(!tracker.isPointerInside)
        #expect(tracker.update(
            enabled: true,
            buttonsDown: false,
            point: inside,
            toggleFrame: toggle,
            screenFrame: screen
        ) == .entered)
    }

    @Test func testEntryCancelsRehideAndRevealsOnlyWhenCollapsed() {
        #expect(MenuBarHoverPolicy.decide(
            transition: .entered,
            isCollapsed: true,
            autoRehide: true
        ) == .init(cancelRehide: true, reveal: true, scheduleRehide: false))
        #expect(MenuBarHoverPolicy.decide(
            transition: .entered,
            isCollapsed: false,
            autoRehide: true
        ) == .init(cancelRehide: true, reveal: false, scheduleRehide: false))
    }

    @Test func testExitFollowsAutoRehidePreference() {
        #expect(MenuBarHoverPolicy.decide(
            transition: .exited,
            isCollapsed: false,
            autoRehide: true
        ) == .init(cancelRehide: false, reveal: false, scheduleRehide: true))
        #expect(MenuBarHoverPolicy.decide(
            transition: .exited,
            isCollapsed: false,
            autoRehide: false
        ) == .init(cancelRehide: false, reveal: false, scheduleRehide: false))
        #expect(MenuBarHoverPolicy.decide(
            transition: .exited,
            isCollapsed: true,
            autoRehide: true
        ) == .init(cancelRehide: false, reveal: false, scheduleRehide: false))
    }

    // MARK: - Reveal band

    /// Right edge of a 14-inch MacBook Pro's notch.
    private let notchRightEdge: CGFloat = 848.5

    @Test func testRevealBandStartsAtTheNotchAndEndsAtTheToggle() {
        #expect(MenuBarHoverRegion.revealBand(
            toggleFrame: toggle,
            screenFrame: screen,
            statusAreaMinX: notchRightEdge
        ) == CGRect(x: 848.5, y: 949, width: 613.5, height: 33))
    }

    @Test func testRevealBandStartsMidScreenWithoutANotch() {
        #expect(MenuBarHoverRegion.revealBand(
            toggleFrame: toggle,
            screenFrame: screen,
            statusAreaMinX: nil
        ) == CGRect(x: 756, y: 949, width: 706, height: 33))
    }

    @Test func testRevealBandFollowsAToggleLeftOfItsStart() {
        let crowdedToggle = CGRect(x: 600, y: 949, width: 32, height: 33)

        #expect(MenuBarHoverRegion.revealBand(
            toggleFrame: crowdedToggle,
            screenFrame: screen,
            statusAreaMinX: notchRightEdge
        ) == CGRect(x: 600, y: 949, width: 32, height: 33))
    }

    @Test func testRevealBandNeedsAValidToggle() {
        #expect(MenuBarHoverRegion.revealBand(
            toggleFrame: nil,
            screenFrame: screen,
            statusAreaMinX: notchRightEdge
        ) == nil)
    }

    @Test func testAppMenusDoNotStartAHoverButKeepARevealedOne() {
        var tracker = MenuBarHoverTracker()
        let reveal = MenuBarHoverRegion.revealBand(
            toggleFrame: toggle,
            screenFrame: screen,
            statusAreaMinX: notchRightEdge
        )
        let retain = MenuBarHoverRegion.band(toggleFrame: toggle, screenFrame: screen)
        func move(to point: CGPoint) -> MenuBarHoverTransition? {
            tracker.update(
                enabled: true,
                buttonsDown: false,
                point: point,
                revealBand: reveal,
                retainBand: retain
            )
        }

        // Over File and Edit, left of the notch: nothing.
        #expect(move(to: CGPoint(x: 300, y: 960)) == nil)
        #expect(!tracker.isPointerInside)
        // Next to the status icons: the hover starts.
        #expect(move(to: CGPoint(x: 1000, y: 960)) == .entered)
        // Back across the bar to the app menus: still the same hover.
        #expect(move(to: CGPoint(x: 300, y: 960)) == nil)
        #expect(tracker.isPointerInside)
        // Out of the bar entirely: it ends.
        #expect(move(to: CGPoint(x: 300, y: 900)) == .exited)
    }

    @Test func testARevealedBarCountsAPointerAlreadyOverTheAppMenus() {
        var tracker = MenuBarHoverTracker()
        let reveal = MenuBarHoverRegion.revealBand(
            toggleFrame: toggle,
            screenFrame: screen,
            statusAreaMinX: notchRightEdge
        )
        let retain = MenuBarHoverRegion.band(toggleFrame: toggle, screenFrame: screen)
        let overFile = CGPoint(x: 300, y: 960)
        func check(revealed: Bool, at point: CGPoint = overFile) -> MenuBarHoverTransition? {
            tracker.update(
                enabled: true,
                buttonsDown: false,
                point: point,
                revealBand: reveal,
                retainBand: retain,
                isRevealed: revealed
            )
        }

        // Collapsed, resting over File: not a hover.
        #expect(check(revealed: false) == nil)
        // The shortcut reveals with the pointer still there: now it counts,
        // so the entry cancels the rehide timer instead of letting it run.
        #expect(check(revealed: true) == .entered)
        #expect(tracker.isPointerInside)
        #expect(MenuBarHoverPolicy.decide(
            transition: .entered,
            isCollapsed: false,
            autoRehide: true
        ).cancelRehide)
        // Leaving the bar still ends it, which starts the timer as before.
        #expect(check(revealed: true, at: CGPoint(x: 300, y: 900)) == .exited)
    }
}
