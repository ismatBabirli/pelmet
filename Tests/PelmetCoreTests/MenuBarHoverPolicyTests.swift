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
}
