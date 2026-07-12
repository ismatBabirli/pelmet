import Testing
@testable import PelmetCore
import CoreGraphics

/// Fixture geometry and frames are real values captured by the probe
/// harness on a notched 14" MacBook Pro running macOS 26.5 (Tahoe):
/// screen 1512×982, notch x∈[663, 848], menu bar band 33pt at y=949.
struct MenuBarLayoutClassifierTests {

    private let geometry = MenuBarGeometry(
        screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        notchRect: CGRect(x: 663, y: 950, width: 185, height: 32),
        menuBarHeight: 33
    )

    private func bar(_ minX: CGFloat, _ width: CGFloat) -> CGRect {
        CGRect(x: minX, y: 949, width: width, height: 33)
    }

    private func win(_ minX: CGFloat, _ width: CGFloat, pid: Int32? = nil) -> RawStatusWindow {
        RawStatusWindow(frame: bar(minX, width), ownerPID: pid)
    }

    // MARK: - Swallowed detection (expanded)

    @Test func testExpandedOverflowCountsUnderAndLeftOfNotch() {
        let raw = [
            win(900, 40),   // visible, right of notch
            win(1000, 40),  // visible
            win(700, 46),   // under the notch
            win(472, 46),   // left of the notch
        ]
        let result = MenuBarLayoutClassifier.classify(
            rawItems: raw,
            ownSeparatorFrame: bar(1170, 26),
            ownToggleFrame: bar(1198, 38),
            isCollapsed: false,
            geometry: geometry
        )
        #expect(result.swallowedCount == 2)
        #expect(result.offscreenLeftCount == 0)
        #expect(result.separatorHealth == .visible)
        #expect(result.toggleVisible)
    }

    // MARK: - Stale twin windows (Tahoe leaves them at old positions)

    @Test func testExpandedNegativeXWindowsAreGhostsNotSwallowed() {
        // After an ordinary expand, the previous collapse's mirror windows
        // linger past the left screen edge for minutes.
        let raw = [win(-926, 45), win(-444, 31), win(700, 46)]
        let result = MenuBarLayoutClassifier.classify(
            rawItems: raw,
            ownSeparatorFrame: bar(1170, 26),
            ownToggleFrame: bar(1198, 38),
            isCollapsed: false,
            geometry: geometry
        )
        #expect(result.swallowedCount == 1)
        #expect(result.items.filter { $0.visibility == .suspectedGhost }.count == 2)
    }

    @Test func testBirthPositionWindowAtExactlyZeroIsGhost() {
        // Items are born at x == 0 and immediately move to their seeded
        // position; the birth twin can stay behind.
        let raw = [win(0, 26), win(0, 56), win(700, 46)]
        let result = MenuBarLayoutClassifier.classify(
            rawItems: raw,
            ownSeparatorFrame: bar(1170, 26),
            ownToggleFrame: bar(1198, 38),
            isCollapsed: false,
            geometry: geometry
        )
        #expect(result.swallowedCount == 1)
        // The two overlapping birth twins dedupe to one entry first.
        #expect(result.items.filter { $0.visibility == .suspectedGhost }.count == 1)
    }

    @Test func testAllVisibleWhenBarFits() {
        let raw = [win(900, 40), win(1000, 40), win(1100, 40)]
        let result = MenuBarLayoutClassifier.classify(
            rawItems: raw,
            ownSeparatorFrame: bar(1170, 26),
            ownToggleFrame: bar(1198, 38),
            isCollapsed: false,
            geometry: geometry
        )
        #expect(result.swallowedCount == 0)
        #expect(result.items.allSatisfy { $0.visibility == .visible })
    }

    // MARK: - Collapsed state

    @Test func testCollapsedManagedItemsAreOffscreenLeftNotSwallowed() {
        // Separator inflated: frame observed at x=-2818, width 4016.
        let separator = CGRect(x: -2818, y: 949, width: 4016, height: 33)
        let raw = [
            win(-2864, 46), // managed, pushed past the left edge — expected
            win(900, 40),   // always-visible icon
        ]
        let result = MenuBarLayoutClassifier.classify(
            rawItems: raw,
            ownSeparatorFrame: separator,
            ownToggleFrame: bar(1198, 38),
            isCollapsed: true,
            geometry: geometry
        )
        #expect(result.swallowedCount == 0)
        #expect(result.offscreenLeftCount == 1)
        #expect(result.separatorHealth == .unknown)
    }

    @Test func testCollapsedStillOverflowingCountsUnmanagedUnderNotch() {
        // A layout can only swallow right-of-divider items while collapsed
        // when the always-visible set is wide enough to push the inflated
        // separator's END past the left of the notch — items never sit
        // INSIDE the separator's span (a frame there is a stale twin).
        let separator = CGRect(x: -3500, y: 949, width: 4016, height: 33) // maxX = 516 < notch
        let raw = [
            win(-3550, 46), // managed, pushed past the separator's left end
            win(700, 40),   // unmanaged icon that STILL doesn't fit collapsed
        ]
        let result = MenuBarLayoutClassifier.classify(
            rawItems: raw,
            ownSeparatorFrame: separator,
            ownToggleFrame: bar(1198, 38),
            isCollapsed: true,
            geometry: geometry
        )
        #expect(result.swallowedCount == 1)
        #expect(result.offscreenLeftCount == 1)
    }

    // MARK: - Own-item handling

    @Test func testOwnFramesAreExcludedFromTheCount() {
        let separatorFrame = bar(700, 26) // divider itself swallowed
        let result = MenuBarLayoutClassifier.classify(
            rawItems: [win(700, 26), win(1198, 38), win(900, 40)],
            ownSeparatorFrame: separatorFrame,
            ownToggleFrame: bar(1198, 38),
            isCollapsed: false,
            geometry: geometry
        )
        #expect(result.swallowedCount == 0)
        #expect(result.separatorHealth == .swallowed)
    }

    @Test func testToggleUnderNotchReportsNotVisible() {
        let result = MenuBarLayoutClassifier.classify(
            rawItems: [win(900, 40)],
            ownSeparatorFrame: bar(660, 26),
            ownToggleFrame: bar(700, 38),
            isCollapsed: false,
            geometry: geometry
        )
        #expect(!(result.toggleVisible))
        #expect(result.separatorHealth == .swallowed)
    }

    // MARK: - Dedupe (Tahoe double windows and mid-layout ghosts)

    @Test func testExactDuplicateFramesCollapseToOne() {
        let result = MenuBarLayoutClassifier.classify(
            rawItems: [win(700, 46), win(700, 46)],
            ownSeparatorFrame: bar(1170, 26),
            ownToggleFrame: bar(1198, 38),
            isCollapsed: false,
            geometry: geometry
        )
        #expect(result.swallowedCount == 1)
    }

    @Test func testGhostPairOffsetByHalfWidthCollapsesToOne() {
        // Observed on Tahoe during layout churn: the same item backed by two
        // windows offset ~13pt ([854,886] and [867,899]).
        let result = MenuBarLayoutClassifier.classify(
            rawItems: [win(854, 32), win(867, 32)],
            ownSeparatorFrame: bar(1170, 26),
            ownToggleFrame: bar(1198, 38),
            isCollapsed: false,
            geometry: geometry
        )
        #expect(result.items.count == 1)
    }

    @Test func testAdjacentDistinctItemsAreNotMerged() {
        let result = MenuBarLayoutClassifier.classify(
            rawItems: [win(854, 32), win(886, 38)],
            ownSeparatorFrame: bar(1170, 26),
            ownToggleFrame: bar(1198, 38),
            isCollapsed: false,
            geometry: geometry
        )
        #expect(result.items.count == 2)
    }

    // MARK: - Owner PIDs (identity plumbing for the Shelf)

    @Test func testMirrorClusterMergesOwnerPIDs() {
        // A real item backed by its app's window (pid 500) plus an
        // exact-frame Control Center mirror (pid 300) — one item, both PIDs,
        // in order of appearance after the minX sort.
        let result = MenuBarLayoutClassifier.classify(
            rawItems: [win(700, 46, pid: 500), win(700, 46, pid: 300)],
            ownSeparatorFrame: bar(1170, 26),
            ownToggleFrame: bar(1198, 38),
            isCollapsed: false,
            geometry: geometry
        )
        #expect(result.items.count == 1)
        #expect(result.items[0].ownerPIDs == [500, 300])
    }

    @Test func testDuplicatePIDsInAClusterAreNotRepeated() {
        let result = MenuBarLayoutClassifier.classify(
            rawItems: [win(854, 32, pid: 500), win(867, 32, pid: 500)],
            ownSeparatorFrame: bar(1170, 26),
            ownToggleFrame: bar(1198, 38),
            isCollapsed: false,
            geometry: geometry
        )
        #expect(result.items.count == 1)
        #expect(result.items[0].ownerPIDs == [500])
    }

    @Test func testMissingOwnerPIDsAreTolerated() {
        let result = MenuBarLayoutClassifier.classify(
            rawItems: [win(700, 46), win(900, 40, pid: 500)],
            ownSeparatorFrame: bar(1170, 26),
            ownToggleFrame: bar(1198, 38),
            isCollapsed: false,
            geometry: geometry
        )
        #expect(result.items.count == 2)
        let sorted = result.items.sorted { $0.frame.minX < $1.frame.minX }
        #expect(sorted[0].ownerPIDs.isEmpty)
        #expect(sorted[1].ownerPIDs == [500])
    }

    // MARK: - Stale twins inside the inflated separator's span

    @Test func testCollapsedTwinsAtOldExpandedPositionsAreGhosts() {
        // Observed live (macOS 26.5): after a collapse, twins linger at the
        // previous EXPANDED positions — inside the inflated separator's
        // span, where no real item can be. Two twins sat exactly where the
        // notch is, faking "swallowed=2" while everything was hidden.
        let separator = CGRect(x: -384, y: 949, width: 1720, height: 33)
        let result = MenuBarLayoutClassifier.classify(
            rawItems: [
                win(-867, 24),  // genuinely pushed off (left of separator)
                win(813, 24),   // stale twin under the notch
                win(837, 24),   // stale twin under the notch
                win(900, 40),   // stale twin right of the notch
            ],
            ownSeparatorFrame: separator,
            ownToggleFrame: bar(1336, 18),
            isCollapsed: true,
            geometry: geometry
        )
        #expect(result.swallowedCount == 0)
        #expect(result.offscreenLeftCount == 1)
        #expect(result.items.filter { $0.visibility == .suspectedGhost }.count == 3)
    }

    @Test func testExpandedItemsBesideTheThinSeparatorAreNotGhosts() {
        // Expanded, the separator is 10pt wide — adjacent items touch but
        // never substantially overlap it.
        let result = MenuBarLayoutClassifier.classify(
            rawItems: [win(1160, 40), win(1210, 40)],
            ownSeparatorFrame: bar(1200, 10),
            ownToggleFrame: bar(1250, 38),
            isCollapsed: false,
            geometry: geometry
        )
        #expect(result.items.filter { $0.visibility == .suspectedGhost }.isEmpty)
        #expect(result.items.count == 2)
    }

    // MARK: - Non-item windows at the status level

    @Test func testOversizedPanelInTheBandIsIgnored() {
        // Observed on Tahoe: a 450pt-wide clipboard-manager window at the
        // status-item window level.
        let result = MenuBarLayoutClassifier.classify(
            rawItems: [win(1062, 450), win(700, 40)],
            ownSeparatorFrame: bar(1170, 26),
            ownToggleFrame: bar(1198, 38),
            isCollapsed: false,
            geometry: geometry
        )
        #expect(result.items.count == 1)
        #expect(result.swallowedCount == 1)
    }

    @Test func testWindowsOutsideTheMenuBarBandAreIgnored() {
        let floatingPanel = RawStatusWindow(frame: CGRect(x: 700, y: 400, width: 40, height: 33))
        let result = MenuBarLayoutClassifier.classify(
            rawItems: [floatingPanel],
            ownSeparatorFrame: bar(1170, 26),
            ownToggleFrame: bar(1198, 38),
            isCollapsed: false,
            geometry: geometry
        )
        #expect(result.items.count == 0)
    }

    // MARK: - No notch

    @Test func testNoNotchNeverReportsSwallowed() {
        let flat = MenuBarGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            notchRect: nil,
            menuBarHeight: 24
        )
        let raw = [RawStatusWindow(frame: CGRect(x: 700, y: 957, width: 40, height: 24))]
        let result = MenuBarLayoutClassifier.classify(
            rawItems: raw,
            ownSeparatorFrame: CGRect(x: 1170, y: 957, width: 26, height: 24),
            ownToggleFrame: CGRect(x: 1198, y: 957, width: 38, height: 24),
            isCollapsed: false,
            geometry: flat
        )
        #expect(result.swallowedCount == 0)
        #expect(result.separatorHealth == .visible)
        #expect(result.toggleVisible)
    }
}
