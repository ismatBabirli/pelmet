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

    // MARK: - Swallowed detection (expanded)

    @Test func testExpandedOverflowCountsUnderAndLeftOfNotch() {
        let raw = [
            bar(900, 40),   // visible, right of notch
            bar(1000, 40),  // visible
            bar(700, 46),   // under the notch
            bar(472, 46),   // left of the notch
        ]
        let result = MenuBarLayoutClassifier.classify(
            rawItemFrames: raw,
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
        let raw = [bar(-926, 45), bar(-444, 31), bar(700, 46)]
        let result = MenuBarLayoutClassifier.classify(
            rawItemFrames: raw,
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
        let raw = [bar(0, 26), bar(0, 56), bar(700, 46)]
        let result = MenuBarLayoutClassifier.classify(
            rawItemFrames: raw,
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
        let raw = [bar(900, 40), bar(1000, 40), bar(1100, 40)]
        let result = MenuBarLayoutClassifier.classify(
            rawItemFrames: raw,
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
            bar(-2864, 46), // managed, pushed past the left edge — expected
            bar(900, 40),   // always-visible icon
        ]
        let result = MenuBarLayoutClassifier.classify(
            rawItemFrames: raw,
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
        let separator = CGRect(x: -2818, y: 949, width: 4016, height: 33)
        let raw = [
            bar(-2864, 46), // managed
            bar(700, 40),   // unmanaged icon that STILL doesn't fit collapsed
        ]
        let result = MenuBarLayoutClassifier.classify(
            rawItemFrames: raw,
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
            rawItemFrames: [separatorFrame, bar(1198, 38), bar(900, 40)],
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
            rawItemFrames: [bar(900, 40)],
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
            rawItemFrames: [bar(700, 46), bar(700, 46)],
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
            rawItemFrames: [bar(854, 32), bar(867, 32)],
            ownSeparatorFrame: bar(1170, 26),
            ownToggleFrame: bar(1198, 38),
            isCollapsed: false,
            geometry: geometry
        )
        #expect(result.items.count == 1)
    }

    @Test func testAdjacentDistinctItemsAreNotMerged() {
        let result = MenuBarLayoutClassifier.classify(
            rawItemFrames: [bar(854, 32), bar(886, 38)],
            ownSeparatorFrame: bar(1170, 26),
            ownToggleFrame: bar(1198, 38),
            isCollapsed: false,
            geometry: geometry
        )
        #expect(result.items.count == 2)
    }

    // MARK: - Non-item windows at the status level

    @Test func testOversizedPanelInTheBandIsIgnored() {
        // Observed on Tahoe: a 450pt-wide clipboard-manager window at the
        // status-item window level.
        let result = MenuBarLayoutClassifier.classify(
            rawItemFrames: [bar(1062, 450), bar(700, 40)],
            ownSeparatorFrame: bar(1170, 26),
            ownToggleFrame: bar(1198, 38),
            isCollapsed: false,
            geometry: geometry
        )
        #expect(result.items.count == 1)
        #expect(result.swallowedCount == 1)
    }

    @Test func testWindowsOutsideTheMenuBarBandAreIgnored() {
        let floatingPanel = CGRect(x: 700, y: 400, width: 40, height: 33)
        let result = MenuBarLayoutClassifier.classify(
            rawItemFrames: [floatingPanel],
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
        let raw = [CGRect(x: 700, y: 957, width: 40, height: 24)]
        let result = MenuBarLayoutClassifier.classify(
            rawItemFrames: raw,
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
