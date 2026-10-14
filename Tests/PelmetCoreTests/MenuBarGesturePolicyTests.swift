import CoreGraphics
import Testing
@testable import PelmetCore

struct MenuBarGesturePolicyTests {

    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let visible = CGRect(x: 0, y: 0, width: 1512, height: 949)
    private let toggle = CGRect(x: 1430, y: 949, width: 32, height: 33)
    private let reveal = CGRect(x: 848.5, y: 949, width: 613.5, height: 33)

    private let nearIcons = CGPoint(x: 1000, y: 960)
    private let overAppMenus = CGPoint(x: 300, y: 960)
    private let onDesktop = CGPoint(x: 700, y: 400)

    // MARK: - Scroll

    @Test func testScrollStartInsideTheBandRevealsWhileCollapsed() {
        #expect(MenuBarGesturePolicy.revealsOnScroll(
            enabled: true, isCollapsed: true, isGestureStart: true,
            point: nearIcons, revealBand: reveal
        ))
    }

    @Test func testScrollIgnoresTheRestOfAGestureAndOtherPlaces() {
        #expect(!MenuBarGesturePolicy.revealsOnScroll(
            enabled: true, isCollapsed: true, isGestureStart: false,
            point: nearIcons, revealBand: reveal
        ))
        #expect(!MenuBarGesturePolicy.revealsOnScroll(
            enabled: true, isCollapsed: true, isGestureStart: true,
            point: overAppMenus, revealBand: reveal
        ))
        #expect(!MenuBarGesturePolicy.revealsOnScroll(
            enabled: true, isCollapsed: false, isGestureStart: true,
            point: nearIcons, revealBand: reveal
        ))
        #expect(!MenuBarGesturePolicy.revealsOnScroll(
            enabled: false, isCollapsed: true, isGestureStart: true,
            point: nearIcons, revealBand: reveal
        ))
        #expect(!MenuBarGesturePolicy.revealsOnScroll(
            enabled: true, isCollapsed: true, isGestureStart: true,
            point: nearIcons, revealBand: nil
        ))
    }

    // MARK: - Click on empty bar space

    @Test func testClickOnEmptySpaceNearTheIconsReveals() {
        #expect(MenuBarGesturePolicy.revealsOnBarClick(
            enabled: true, isCollapsed: true, point: nearIcons,
            revealBand: reveal, toggleFrame: toggle, hitsOtherStatusItem: false
        ))
    }

    @Test func testClickOnAnItemOrTheToggleBelongsToIt() {
        #expect(!MenuBarGesturePolicy.revealsOnBarClick(
            enabled: true, isCollapsed: true, point: nearIcons,
            revealBand: reveal, toggleFrame: toggle, hitsOtherStatusItem: true
        ))
        #expect(!MenuBarGesturePolicy.revealsOnBarClick(
            enabled: true, isCollapsed: true, point: CGPoint(x: 1440, y: 960),
            revealBand: reveal, toggleFrame: toggle, hitsOtherStatusItem: false
        ))
    }

    @Test func testBarClickNeedsTheSettingACollapseAndTheBand() {
        #expect(!MenuBarGesturePolicy.revealsOnBarClick(
            enabled: false, isCollapsed: true, point: nearIcons,
            revealBand: reveal, toggleFrame: toggle, hitsOtherStatusItem: false
        ))
        #expect(!MenuBarGesturePolicy.revealsOnBarClick(
            enabled: true, isCollapsed: false, point: nearIcons,
            revealBand: reveal, toggleFrame: toggle, hitsOtherStatusItem: false
        ))
        #expect(!MenuBarGesturePolicy.revealsOnBarClick(
            enabled: true, isCollapsed: true, point: overAppMenus,
            revealBand: reveal, toggleFrame: toggle, hitsOtherStatusItem: false
        ))
    }

    // MARK: - Click outside

    private var strip: CGRect {
        MenuBarGesturePolicy.menuBarStrip(screenFrame: screen, visibleFrame: visible, fallbackHeight: 24)
    }

    @Test func testClickOnTheDesktopHidesRevealedIcons() {
        #expect(MenuBarGesturePolicy.hidesOnOutsideClick(
            enabled: true, isCollapsed: false, point: onDesktop,
            menuBarStrips: [strip], isMenuOpen: false, isPelmetWindowOpen: false
        ))
    }

    @Test func testClickAnywhereInAMenuBarKeepsThemShown() {
        let external = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
        let externalStrip = MenuBarGesturePolicy.menuBarStrip(
            screenFrame: external,
            visibleFrame: CGRect(x: 1512, y: 0, width: 1920, height: 1056),
            fallbackHeight: 24
        )

        #expect(!MenuBarGesturePolicy.hidesOnOutsideClick(
            enabled: true, isCollapsed: false, point: overAppMenus,
            menuBarStrips: [strip, externalStrip], isMenuOpen: false, isPelmetWindowOpen: false
        ))
        #expect(!MenuBarGesturePolicy.hidesOnOutsideClick(
            enabled: true, isCollapsed: false, point: CGPoint(x: 2000, y: 1070),
            menuBarStrips: [strip, externalStrip], isMenuOpen: false, isPelmetWindowOpen: false
        ))
    }

    @Test func testOpenMenusAndPelmetWindowsHoldTheReveal() {
        #expect(!MenuBarGesturePolicy.hidesOnOutsideClick(
            enabled: true, isCollapsed: false, point: onDesktop,
            menuBarStrips: [strip], isMenuOpen: true, isPelmetWindowOpen: false
        ))
        #expect(!MenuBarGesturePolicy.hidesOnOutsideClick(
            enabled: true, isCollapsed: false, point: onDesktop,
            menuBarStrips: [strip], isMenuOpen: false, isPelmetWindowOpen: true
        ))
    }

    @Test func testOutsideClickNeedsTheSettingAndARevealedBar() {
        #expect(!MenuBarGesturePolicy.hidesOnOutsideClick(
            enabled: false, isCollapsed: false, point: onDesktop,
            menuBarStrips: [strip], isMenuOpen: false, isPelmetWindowOpen: false
        ))
        #expect(!MenuBarGesturePolicy.hidesOnOutsideClick(
            enabled: true, isCollapsed: true, point: onDesktop,
            menuBarStrips: [strip], isMenuOpen: false, isPelmetWindowOpen: false
        ))
    }

    @Test func testStripUsesTheGapAboveTheVisibleFrame() {
        #expect(strip == CGRect(x: 0, y: 949, width: 1512, height: 33))
    }

    @Test func testHiddenMenuBarFallsBackToTheBarThickness() {
        #expect(MenuBarGesturePolicy.menuBarStrip(
            screenFrame: screen, visibleFrame: screen, fallbackHeight: 24
        ) == CGRect(x: 0, y: 958, width: 1512, height: 24))
    }
}
