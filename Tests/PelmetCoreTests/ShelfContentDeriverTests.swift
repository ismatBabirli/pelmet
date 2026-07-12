import Testing
@testable import PelmetCore
import CoreGraphics

/// Same fixture geometry as the classifier tests: 14" MacBook Pro,
/// notch x∈[663, 848], band 33pt at y=949. The deriver consumes classifier
/// output, so fixtures are built straight from ClassifiedItems.
struct ShelfContentDeriverTests {

    private let controlCenter: Int32 = 300
    private let ownPID: Int32 = 999

    private func bar(_ minX: CGFloat, _ width: CGFloat = 40) -> CGRect {
        CGRect(x: minX, y: 949, width: width, height: 33)
    }

    private func swallowed(_ minX: CGFloat, pids: [Int32]) -> ClassifiedItem {
        ClassifiedItem(frame: bar(minX), visibility: .swallowedByNotch, ownerPIDs: pids)
    }

    private func classification(_ items: [ClassifiedItem]) -> LayoutClassification {
        LayoutClassification(items: items, separatorHealth: .visible, toggleVisible: true)
    }

    private let apps: [Int32: RunningAppInfo] = [
        500: RunningAppInfo(pid: 500, bundleID: "com.example.dropbox", localizedName: "Dropbox"),
        501: RunningAppInfo(pid: 501, bundleID: "com.example.vpn", localizedName: "TunnelBear"),
    ]

    private func derive(
        _ items: [ClassifiedItem],
        engineItems: [EngineItemDescriptor] = []
    ) -> [ShelfEntryModel] {
        ShelfContentDeriver.derive(
            classification: classification(items),
            apps: apps,
            controlCenterPID: controlCenter,
            ownPID: ownPID,
            engineItems: engineItems
        )
    }

    // MARK: - Tier 0 with owners (≤ Sequoia)

    @Test func testDistinctOwnersBecomeNamedEntriesSortedLeftToRight() {
        let entries = derive([
            swallowed(700, pids: [501, controlCenter]),
            swallowed(472, pids: [500]),
        ])
        #expect(entries.count == 2)
        #expect(entries[0].kind == .app(pid: 500, name: "Dropbox", itemCount: 1))
        #expect(entries[1].kind == .app(pid: 501, name: "TunnelBear", itemCount: 1))
        #expect(entries[0].frame.minX < entries[1].frame.minX)
    }

    @Test func testMixedClusterPrefersNonControlCenterPID() {
        let entries = derive([swallowed(700, pids: [controlCenter, 500])])
        #expect(entries.count == 1)
        #expect(entries[0].kind == .app(pid: 500, name: "Dropbox", itemCount: 1))
    }

    @Test func testConsecutiveSameOwnerItemsAreGrouped() {
        let entries = derive([
            swallowed(472, pids: [500]),
            swallowed(520, pids: [500]),
            swallowed(700, pids: [501]),
        ])
        #expect(entries.count == 2)
        #expect(entries[0].kind == .app(pid: 500, name: "Dropbox", itemCount: 2))
        #expect(entries[0].frame == bar(472)) // leftmost member's frame
        #expect(entries[1].kind == .app(pid: 501, name: "TunnelBear", itemCount: 1))
    }

    @Test func testNonConsecutiveSameOwnerItemsAreNotGrouped() {
        let entries = derive([
            swallowed(472, pids: [500]),
            swallowed(520, pids: [501]),
            swallowed(700, pids: [500]),
        ])
        #expect(entries.count == 3)
    }

    // MARK: - Tier 0 anonymous (Tahoe: everything Control-Center-owned)

    @Test func testAllControlCenterOwnersBecomeUnknownOrdinals() {
        let entries = derive([
            swallowed(472, pids: [controlCenter]),
            swallowed(700, pids: [controlCenter]),
        ])
        #expect(entries.count == 2)
        #expect(entries[0].kind == .unknown(ordinal: 1))
        #expect(entries[1].kind == .unknown(ordinal: 2))
    }

    @Test func testDeadPIDDegradesToUnknownWithoutDisturbingNeighbors() {
        let entries = derive([
            swallowed(472, pids: [500]),
            swallowed(700, pids: [777]), // not in `apps` — process died
        ])
        #expect(entries.count == 2)
        #expect(entries[0].kind == .app(pid: 500, name: "Dropbox", itemCount: 1))
        #expect(entries[1].kind == .unknown(ordinal: 1))
    }

    @Test func testEmptyOwnerListIsUnknown() {
        let entries = derive([swallowed(700, pids: [])])
        #expect(entries.count == 1)
        #expect(entries[0].kind == .unknown(ordinal: 1))
    }

    // MARK: - Exclusions (badge parity with what the badge counts)

    @Test func testOwnWindowsAreDropped() {
        let entries = derive([
            swallowed(472, pids: [ownPID]),
            swallowed(700, pids: [500]),
        ])
        #expect(entries.count == 1)
        #expect(entries[0].kind == .app(pid: 500, name: "Dropbox", itemCount: 1))
    }

    @Test func testGhostsAndOffscreenLeftAreExcluded() {
        let items = [
            ClassifiedItem(frame: bar(-2864), visibility: .offscreenLeft, ownerPIDs: [500]),
            ClassifiedItem(frame: bar(0), visibility: .suspectedGhost, ownerPIDs: [501]),
            ClassifiedItem(frame: bar(900), visibility: .visible, ownerPIDs: [500]),
            swallowed(700, pids: [501]),
        ]
        let entries = derive(items)
        #expect(entries.count == 1)
        #expect(entries[0].kind == .app(pid: 501, name: "TunnelBear", itemCount: 1))
    }

    @Test func testEmptyClassificationYieldsNoEntries() {
        #expect(derive([]).isEmpty)
    }

    // MARK: - Engine enrichment

    @Test func testEngineItemMatchesByFrameWithinTolerance() {
        let descriptor = EngineItemDescriptor(
            token: "t1", title: "Dropbox — Syncing", ownerPID: 500,
            frame: bar(700 + ShelfContentDeriver.frameMatchTolerance) // midX off by exactly the tolerance
        )
        let entries = derive([swallowed(700, pids: [controlCenter])], engineItems: [descriptor])
        #expect(entries.count == 1)
        #expect(entries[0].kind == .engineItem(token: "t1", title: "Dropbox — Syncing", ownerPID: 500))
    }

    @Test func testEngineItemBeyondToleranceDoesNotMatch() {
        let descriptor = EngineItemDescriptor(
            token: "t1", title: "Dropbox", ownerPID: 500,
            frame: bar(700 + ShelfContentDeriver.frameMatchTolerance + 1)
        )
        let entries = derive([swallowed(700, pids: [controlCenter])], engineItems: [descriptor])
        #expect(entries.count == 1)
        // Falls back to an anonymous row; the unmatched descriptor is dropped.
        #expect(entries[0].kind == .unknown(ordinal: 1))
    }

    @Test func testFramelessEngineItemMatchesByUniqueOwnerPID() {
        let descriptor = EngineItemDescriptor(token: "t2", title: "TunnelBear", ownerPID: 501, frame: nil)
        let entries = derive([swallowed(700, pids: [501])], engineItems: [descriptor])
        #expect(entries.count == 1)
        #expect(entries[0].kind == .engineItem(token: "t2", title: "TunnelBear", ownerPID: 501))
    }

    @Test func testFramelessEngineItemWithAmbiguousPIDDoesNotMatch() {
        let descriptor = EngineItemDescriptor(token: "t3", title: "Dropbox", ownerPID: 500, frame: nil)
        let entries = derive(
            [swallowed(472, pids: [500]), swallowed(700, pids: [500])],
            engineItems: [descriptor]
        )
        // Two candidate items for one descriptor — no guess. And with the
        // engine present, same-app rows are never grouped.
        #expect(entries.count == 2)
        #expect(entries.allSatisfy {
            $0.kind == .app(pid: 500, name: "Dropbox", itemCount: 1)
        })
    }

    @Test func testEngineItemWithNoClassifiedCounterpartIsIgnored() {
        // Badge parity: the engine can never add rows the badge didn't count.
        let descriptor = EngineItemDescriptor(token: "t4", title: "Phantom", ownerPID: 502, frame: bar(1100))
        let entries = derive([swallowed(700, pids: [500])], engineItems: [descriptor])
        #expect(entries.count == 1)
        #expect(entries[0].kind == .app(pid: 500, name: "Dropbox", itemCount: 1))
    }

    @Test func testTitlelessDescriptorFallsBackToAppName() {
        let descriptor = EngineItemDescriptor(token: "t6", title: nil, ownerPID: 500, frame: bar(700))
        let entries = derive([swallowed(700, pids: [controlCenter])], engineItems: [descriptor])
        #expect(entries.count == 1)
        #expect(entries[0].kind == .engineItem(token: "t6", title: "Dropbox", ownerPID: 500))
    }

    @Test func testTitlelessOwnerlessDescriptorGetsNumberedFallback() {
        // The user-visible bug: engine granted but identity unresolved must
        // still render numbered rows, never identical "Hidden item" twins.
        let descriptors = [
            EngineItemDescriptor(token: "t7", title: nil, ownerPID: nil, frame: bar(472)),
            EngineItemDescriptor(token: "t8", title: nil, ownerPID: nil, frame: bar(700)),
        ]
        let entries = derive(
            [swallowed(472, pids: [controlCenter]), swallowed(700, pids: [controlCenter])],
            engineItems: descriptors
        )
        #expect(entries.count == 2)
        #expect(entries[0].kind == .engineItem(token: "t7", title: "Hidden item 1", ownerPID: nil))
        #expect(entries[1].kind == .engineItem(token: "t8", title: "Hidden item 2", ownerPID: nil))
    }

    @Test func testEachDescriptorEnrichesOnlyOneItem() {
        let descriptor = EngineItemDescriptor(token: "t5", title: "Dropbox", ownerPID: 500, frame: bar(472))
        let entries = derive(
            [swallowed(472, pids: [500]), swallowed(476, pids: [500])],
            engineItems: [descriptor]
        )
        #expect(entries.count == 2)
        #expect(entries.filter {
            if case .engineItem = $0.kind { return true } else { return false }
        }.count == 1)
    }
}
