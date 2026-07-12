import Testing
@testable import PelmetCore
import CoreGraphics

struct ShelfPlacementTests {

    private let geometry = MenuBarGeometry(
        screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        notchRect: CGRect(x: 663, y: 950, width: 185, height: 32),
        menuBarHeight: 33
    )
    private let panelSize = CGSize(width: 320, height: 180)

    @Test func testCenteredOnAnchorAndBelowTheMenuBarBand() {
        let anchor = CGRect(x: 1198, y: 949, width: 38, height: 33)
        let frame = ShelfPlacement.panelFrame(panelSize: panelSize, anchorFrame: anchor, geometry: geometry)
        let expectedMaxY: CGFloat = 982 - 33 - 6 // screen top − menu bar − gap
        #expect(frame.midX == anchor.midX)
        #expect(frame.maxY == expectedMaxY)
        #expect(frame.size == panelSize)
    }

    @Test func testClampedAtTheRightEdge() {
        // Toggle near the right edge on a 14": centering would overflow.
        let anchor = CGRect(x: 1460, y: 949, width: 38, height: 33)
        let frame = ShelfPlacement.panelFrame(panelSize: panelSize, anchorFrame: anchor, geometry: geometry)
        let expectedMaxX: CGFloat = 1512 - 8
        #expect(frame.maxX == expectedMaxX)
        #expect(frame.minX >= 8)
    }

    @Test func testClampedAtTheLeftEdge() {
        let anchor = CGRect(x: 10, y: 949, width: 38, height: 33)
        let frame = ShelfPlacement.panelFrame(panelSize: panelSize, anchorFrame: anchor, geometry: geometry)
        #expect(frame.minX == 8)
    }

    @Test func testNoAnchorFallsBackToNotchCenter() {
        let frame = ShelfPlacement.panelFrame(panelSize: panelSize, anchorFrame: nil, geometry: geometry)
        #expect(frame.midX == geometry.notchRect!.midX)
    }

    @Test func testNoAnchorNoNotchFallsBackToScreenCenter() {
        let flat = MenuBarGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            notchRect: nil,
            menuBarHeight: 24
        )
        let frame = ShelfPlacement.panelFrame(panelSize: panelSize, anchorFrame: nil, geometry: flat)
        #expect(frame.midX == 756)
    }

    @Test func testSecondaryDisplayOriginIsRespected() {
        // A display left of the primary: negative-x screen frame.
        let external = MenuBarGeometry(
            screenFrame: CGRect(x: -1920, y: 100, width: 1920, height: 1080),
            notchRect: nil,
            menuBarHeight: 24
        )
        let anchor = CGRect(x: -100, y: 1150, width: 38, height: 24)
        let frame = ShelfPlacement.panelFrame(panelSize: panelSize, anchorFrame: anchor, geometry: external)
        #expect(frame.maxX <= -8)
        #expect(frame.maxY == external.screenFrame.maxY - 24 - 6)
    }
}
