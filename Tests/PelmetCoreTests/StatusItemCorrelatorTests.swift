import Testing
@testable import PelmetCore
import CoreGraphics

/// Fixture values mirror the classifier tests: band 33pt at y=949.
struct StatusItemCorrelatorTests {

    private func bar(_ minX: CGFloat, _ width: CGFloat = 40) -> CGRect {
        CGRect(x: minX, y: 949, width: width, height: 33)
    }

    private func item(_ minX: CGFloat, _ width: CGFloat = 40) -> ClassifiedItem {
        ClassifiedItem(frame: bar(minX, width), visibility: .visible)
    }

    @Test func testExactFrameObservationMatches() {
        let result = StatusItemCorrelator.correlate(
            classified: [item(700, 46)],
            observed: [ItemObservation(pid: 500, title: "VPN", frame: bar(700, 46))]
        )
        #expect(result[0].observation?.pid == 500)
    }

    @Test func testSmallOffsetStillMatches() {
        let result = StatusItemCorrelator.correlate(
            classified: [item(700, 46)],
            observed: [ItemObservation(pid: 500, title: nil, frame: bar(703, 46))]
        )
        #expect(result[0].observation?.pid == 500)
    }

    @Test func testAdjacentItemsNeverCrossMatch() {
        // Real adjacent frames [854,886] and [886,924]: zero overlap.
        let result = StatusItemCorrelator.correlate(
            classified: [item(854, 32), item(886, 38)],
            observed: [
                ItemObservation(pid: 500, title: nil, frame: bar(854, 32)),
                ItemObservation(pid: 501, title: nil, frame: bar(886, 38)),
            ]
        )
        #expect(result[0].observation?.pid == 500)
        #expect(result[1].observation?.pid == 501)
    }

    @Test func testItemWithoutObservationGetsNil() {
        let result = StatusItemCorrelator.correlate(
            classified: [item(700), item(900)],
            observed: [ItemObservation(pid: 500, title: nil, frame: bar(700))]
        )
        #expect(result[0].observation != nil)
        #expect(result[1].observation == nil)
    }

    @Test func testTwoObservationsOverOneFrameBestOverlapWins() {
        let result = StatusItemCorrelator.correlate(
            classified: [item(700, 40)],
            observed: [
                ItemObservation(pid: 500, title: nil, frame: bar(715, 40)), // 25pt overlap
                ItemObservation(pid: 501, title: nil, frame: bar(702, 40)), // 38pt overlap
            ]
        )
        #expect(result[0].observation?.pid == 501)
    }

    @Test func testEachObservationUsedAtMostOnce() {
        // One observation overlapping two near-duplicate frames: only the
        // stronger match gets it.
        let result = StatusItemCorrelator.correlate(
            classified: [item(700, 40), item(706, 40)],
            observed: [ItemObservation(pid: 500, title: nil, frame: bar(700, 40))]
        )
        #expect(result[0].observation?.pid == 500)
        #expect(result[1].observation == nil)
    }

    @Test func testFramelessObservationNeverMatches() {
        let result = StatusItemCorrelator.correlate(
            classified: [item(700)],
            observed: [ItemObservation(pid: 500, title: "Ghost", frame: nil)]
        )
        #expect(result[0].observation == nil)
    }

    @Test func testBelowMinimumOverlapDoesNotMatch() {
        // 15pt overlap of a 40pt-wide pair is under the 50% threshold.
        let result = StatusItemCorrelator.correlate(
            classified: [item(700, 40)],
            observed: [ItemObservation(pid: 500, title: nil, frame: bar(725, 40))]
        )
        #expect(result[0].observation == nil)
    }

    @Test func testTieBrokenByMidXDistance() {
        // Two same-width observations with equal overlap against one item;
        // the one whose center is closer wins.
        let result = StatusItemCorrelator.correlate(
            classified: [item(700, 40)],
            observed: [
                ItemObservation(pid: 500, title: nil, frame: bar(680, 60)), // wider, same 40pt overlap
                ItemObservation(pid: 501, title: nil, frame: bar(700, 40)), // exact
            ]
        )
        #expect(result[0].observation?.pid == 501)
    }
}

struct TitleHygieneTests {

    @Test func testMeaningfulTitlePasses() {
        #expect(TitleHygiene.meaningfulTitle("Syncing 3 files", appName: "Dropbox", bundleID: "com.dropbox.app") == "Syncing 3 files")
    }

    @Test func testJunkIsRejected() {
        #expect(TitleHygiene.meaningfulTitle("menubaricon_v3", appName: "App", bundleID: nil) == nil)
        #expect(TitleHygiene.meaningfulTitle("com.dropbox.app.statusitem", appName: "Dropbox", bundleID: "com.dropbox.app") == nil)
        #expect(TitleHygiene.meaningfulTitle("", appName: "App", bundleID: nil) == nil)
        #expect(TitleHygiene.meaningfulTitle("   ", appName: "App", bundleID: nil) == nil)
        #expect(TitleHygiene.meaningfulTitle("12345", appName: "App", bundleID: nil) == nil)
        #expect(TitleHygiene.meaningfulTitle(String(repeating: "x", count: 41), appName: "App", bundleID: nil) == nil)
        #expect(TitleHygiene.meaningfulTitle(nil, appName: "App", bundleID: nil) == nil)
    }

    @Test func testAppNameEchoIsRejected() {
        #expect(TitleHygiene.meaningfulTitle("Dropbox", appName: "Dropbox", bundleID: nil) == nil)
        #expect(TitleHygiene.meaningfulTitle("dropbox", appName: "Dropbox", bundleID: nil) == nil)
    }

    @Test func testSingleDotSurvives() {
        #expect(TitleHygiene.meaningfulTitle("Backing up…", appName: "Arq", bundleID: nil) == "Backing up…")
        #expect(TitleHygiene.meaningfulTitle("v2.1 ready", appName: "App", bundleID: nil) == "v2.1 ready")
    }
}
