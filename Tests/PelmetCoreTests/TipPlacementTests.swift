import Testing
@testable import PelmetCore
import CoreGraphics

struct TipPlacementTests {

    // 14" notched MacBook: 1512×982, 38pt menu bar. The toggle button's
    // window sits flush under the screen top.
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let anchor = CGRect(x: 1080, y: 944, width: 56, height: 38)
    private let popSize = CGSize(width: 340, height: 185)

    private func frame(x: CGFloat, y: CGFloat) -> CGRect {
        CGRect(origin: CGPoint(x: x, y: y), size: popSize)
    }

    @Test func testAttachedPlacementIsLeftAlone() {
        // Arrow tip flush with the anchor's bottom edge — the healthy case.
        let popover = frame(x: anchor.midX - popSize.width / 2, y: anchor.minY - popSize.height)
        #expect(TipPlacement.correctedFrame(
            popoverFrame: popover, anchorRect: anchor, screenFrame: screen
        ) == nil)
    }

    @Test func testSmallOffsetWithinToleranceIsLeftAlone() {
        let popover = frame(x: anchor.midX - popSize.width / 2, y: anchor.minY - popSize.height - 12)
        #expect(TipPlacement.correctedFrame(
            popoverFrame: popover, anchorRect: anchor, screenFrame: screen
        ) == nil)
    }

    @Test func testDisplacedByOwnHeightIsPulledBackUp() {
        // The observed macOS 26 bug: correct X, one popover-height too low.
        let popover = frame(
            x: anchor.midX - popSize.width / 2,
            y: anchor.minY - 2 * popSize.height
        )
        let corrected = TipPlacement.correctedFrame(
            popoverFrame: popover, anchorRect: anchor, screenFrame: screen
        )
        #expect(corrected?.maxY == anchor.minY)
        // X already covered the anchor: leave it untouched.
        #expect(corrected?.minX == popover.minX)
        #expect(corrected?.size == popSize)
    }

    @Test func testEdgeSlidBubbleStillCoveringAnchorIsLeftAlone() {
        // Anchor near the right screen edge: AppKit slides the bubble left,
        // keeping the arrow on the anchor. midX differs a lot — must not be
        // treated as detached.
        let edgeAnchor = CGRect(x: 1480, y: 944, width: 24, height: 38)
        let popover = frame(
            x: screen.maxX - 8 - popSize.width,
            y: edgeAnchor.minY - popSize.height
        )
        #expect(TipPlacement.correctedFrame(
            popoverFrame: popover, anchorRect: edgeAnchor, screenFrame: screen
        ) == nil)
    }

    @Test func testNonCoveringXIsRecenteredAndClampedAtTheEdge() {
        // Fully detached: wrong Y and nowhere near the anchor horizontally.
        let edgeAnchor = CGRect(x: 1480, y: 944, width: 24, height: 38)
        let popover = frame(x: 200, y: 400)
        let corrected = TipPlacement.correctedFrame(
            popoverFrame: popover, anchorRect: edgeAnchor, screenFrame: screen
        )
        #expect(corrected?.maxY == edgeAnchor.minY)
        // Recentering on midX (1492) would overflow: clamped to the margin.
        #expect(corrected?.maxX == screen.maxX - 8)
        #expect(corrected.map { $0.minX >= screen.minX + 8 } == true)
    }

    @Test func testExternalDisplayWithOffsetOriginClampsWithinThatScreen() {
        // External display arranged left of the primary: negative X origin.
        let extScreen = CGRect(x: -2560, y: 120, width: 2560, height: 1440)
        let extAnchor = CGRect(x: -80, y: extScreen.maxY - 24, width: 30, height: 24)
        let popover = frame(x: -400, y: extScreen.minY + 100)
        let corrected = TipPlacement.correctedFrame(
            popoverFrame: popover, anchorRect: extAnchor, screenFrame: extScreen
        )
        #expect(corrected?.maxY == extAnchor.minY)
        // Anchor sits near the external screen's right edge (x = -65):
        // recentering would cross into the primary; clamp inside extScreen.
        #expect(corrected?.maxX == extScreen.maxX - 8)
    }
}
