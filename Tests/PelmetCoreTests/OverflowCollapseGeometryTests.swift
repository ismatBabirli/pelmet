import CoreGraphics
import Testing
@testable import PelmetCore

struct OverflowCollapseGeometryTests {

    typealias Display = OverflowCollapseGeometry.Display

    /// 14-inch MacBook Pro: 663.5 pt right of the notch.
    private let notchedBuiltIn = Display(width: 1512, statusWidth: 663.5)
    private let external1920 = Display(width: 1920)
    private let external3840 = Display(width: 3840)

    @Test func testNotchedBuiltInUsesOneSpacer() {
        let plan = OverflowCollapseGeometry.plan(displays: [notchedBuiltIn])

        // 0.75 × 663.5 − 64, rounded down. The probe saw 515 pt applied and
        // 535 pt discarded on this display, so 433 pt is well inside.
        #expect(plan.unitLength == 433)
        #expect(plan.activeSpacers == 1)
    }

    @Test func testDisplayWithoutNotchUsesHalfItsWidth() {
        let plan = OverflowCollapseGeometry.plan(displays: [external1920])

        #expect(plan.unitLength == 896)
        #expect(plan.activeSpacers == 2)
    }

    @Test func testNarrowestLimitSetsTheUnitAndWidestAreaSetsTheCount() {
        let plan = OverflowCollapseGeometry.plan(displays: [notchedBuiltIn, external1920])

        #expect(plan.unitLength == 433)
        // 5 × 433 = 2165 ≥ 1920; 4 × 433 = 1732 is not.
        #expect(plan.activeSpacers == 4)
    }

    @Test func testWideExternalBesideTheNotchIsFullyCovered() {
        let plan = OverflowCollapseGeometry.plan(displays: [notchedBuiltIn, external3840])

        // 9 × 433 = 3897 ≥ 3840; 8 × 433 = 3464 is not.
        #expect(plan.activeSpacers == 8)
    }

    @Test func testSpacersAreCappedAtTheRegisteredCount() {
        // Past anything Pelmet expects: an 8K-wide bar beside a scaled Air.
        let plan = OverflowCollapseGeometry.plan(displays: [
            Display(width: 1280, statusWidth: 560),
            Display(width: 7680),
        ])

        #expect(plan.activeSpacers == OverflowCollapseGeometry.spacerCount)
    }

    @Test func testNoDisplaysInflatesNoSpacers() {
        let plan = OverflowCollapseGeometry.plan(displays: [])

        #expect(plan.activeSpacers == 0)
        #expect(plan.unitLength > 0)
    }

    @Test func testStatusWidthNeverExceedsTheDisplay() {
        let display = Display(width: 1440, statusWidth: 2000)

        #expect(display.statusWidth == 1440)
        #expect(OverflowCollapseGeometry.limit(of: display) == 720)
    }

    @Test(arguments: [
        [Display(width: 1512, statusWidth: 663.5)],
        [Display(width: 1728, statusWidth: 763)],
        [Display(width: 1470, statusWidth: 640)],
        [Display(width: 1920)],
        [Display(width: 2560), Display(width: 1512, statusWidth: 663.5)],
        [Display(width: 1024)],
    ])
    func testEveryItemStaysUnderEveryDisplaysLimit(displays: [Display]) {
        let plan = OverflowCollapseGeometry.plan(displays: displays)

        for display in displays {
            #expect(plan.unitLength <= OverflowCollapseGeometry.limit(of: display) - 64)
        }
    }

    @Test(arguments: [
        [Display(width: 1512, statusWidth: 663.5)],
        [Display(width: 1920)],
        [Display(width: 2560), Display(width: 1512, statusWidth: 663.5)],
        [Display(width: 3840), Display(width: 1512, statusWidth: 663.5)],
        [Display(width: 5120), Display(width: 1470, statusWidth: 640)],
        // The widest setup the spacer count is sized for.
        [Display(width: 6016), Display(width: 1280, statusWidth: 560)],
    ])
    func testDividerAndSpacersCoverTheWidestStatusArea(displays: [Display]) {
        let plan = OverflowCollapseGeometry.plan(displays: displays)
        let widest = displays.map(\.statusWidth).max() ?? 0

        #expect(CGFloat(plan.activeSpacers + 1) * plan.unitLength >= widest)
    }
}
