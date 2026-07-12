import Testing
@testable import PelmetCore
import CoreGraphics

struct ScreenCoordinatesTests {

    /// The values WindowListSource produces today: a CG rect at the top of a
    /// 1512×982 primary screen maps to the AppKit menu bar band at y=949.
    @Test func testCGMenuBarRectMapsToAppKitBand() {
        let cg = CGRect(x: 700, y: 0, width: 46, height: 33)
        let appKit = ScreenCoordinates.appKitRect(fromCG: cg, primaryMaxY: 982)
        #expect(appKit == CGRect(x: 700, y: 949, width: 46, height: 33))
    }

    @Test func testRectRoundTrip() {
        let original = CGRect(x: -926, y: 949, width: 45, height: 33)
        let there = ScreenCoordinates.cgRect(fromAppKit: original, primaryMaxY: 982)
        let back = ScreenCoordinates.appKitRect(fromCG: there, primaryMaxY: 982)
        #expect(back == original)
    }

    @Test func testPointRoundTrip() {
        let original = CGPoint(x: 723, y: 965.5)
        let there = ScreenCoordinates.cgPoint(fromAppKit: original, primaryMaxY: 982)
        #expect(there == CGPoint(x: 723, y: 16.5))
        let back = ScreenCoordinates.appKitPoint(fromCG: there, primaryMaxY: 982)
        #expect(back == original)
    }
}
