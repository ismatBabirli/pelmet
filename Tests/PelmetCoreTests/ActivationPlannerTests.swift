import Testing
@testable import PelmetCore
import CoreGraphics

/// Fixture: 14" MacBook Pro — screen 1512×982, notch x∈[663, 848],
/// band 33pt at y=949 (same as the classifier tests).
struct ActivationPlannerTests {

    private let geometry = MenuBarGeometry(
        screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        notchRect: CGRect(x: 663, y: 950, width: 185, height: 32),
        menuBarHeight: 33
    )

    private func bar(_ minX: CGFloat, _ width: CGFloat = 40) -> CGRect {
        CGRect(x: minX, y: 949, width: width, height: 33)
    }

    private func record(
        _ minX: CGFloat,
        _ width: CGFloat = 40,
        visibility: ItemVisibility = .visible,
        pid: Int32? = nil
    ) -> MenuBarItemRecord {
        MenuBarItemRecord(
            frame: bar(minX, width),
            visibility: visibility,
            identity: pid.map { ItemIdentity(pid: $0, bundleIdentifier: nil, appName: "App \($0)", axTitle: nil) }
        )
    }

    private func plan(
        target: MenuBarItemRecord,
        others: [MenuBarItemRecord] = [],
        ownFrames: [CGRect] = [],
        hasAXElement: Bool = false
    ) -> [ActivationStrategy] {
        ActivationPlanner.plan(
            target: target,
            allItems: [target] + others,
            ownFrames: ownFrames,
            geometry: geometry,
            hasAXElement: hasAXElement
        )
    }

    @Test func testVisibleTargetIsJustAClick() {
        let target = record(900)
        let strategies = plan(target: target)
        #expect(strategies == [.syntheticClick(at: CGPoint(x: 920, y: 965.5))])
    }

    @Test func testGhostTargetHasNoPlan() {
        #expect(plan(target: record(0, visibility: .suspectedGhost)).isEmpty)
    }

    @Test func testOffscreenLeftTargetExpandsFirst() {
        let strategies = plan(target: record(-2864, visibility: .offscreenLeft))
        #expect(strategies == [.expandCollapsedBar])
    }

    @Test func testSwallowedWithNeighborGetsFullChain() {
        let target = record(700, visibility: .swallowedByNotch)
        let neighbor = record(900, pid: 500)
        let strategies = plan(target: target, others: [neighbor], hasAXElement: true)
        #expect(strategies.count == 5)
        #expect(strategies[0] == .syntheticClick(at: CGPoint(x: 720, y: 965.5)))
        #expect(strategies[1] == .axPress)
        #expect(strategies[2] == .appMenuClearance)
        if case .dragToExpose(let dragPlan) = strategies[3] {
            #expect(dragPlan.neighborFrame == neighbor.frame)
        } else {
            Issue.record("expected dragToExpose at index 3, got \(strategies[3])")
        }
        #expect(strategies[4] == .clickTargetAfterReflow)
    }

    @Test func testNoAXElementSkipsAXPress() {
        let target = record(700, visibility: .swallowedByNotch)
        let strategies = plan(target: target, others: [record(900, pid: 500)], hasAXElement: false)
        #expect(!strategies.contains(.axPress))
        #expect(strategies.contains(.clickTargetAfterReflow))
    }

    @Test func testNoVisibleNeighborOmitsTheDragPath() {
        let target = record(700, visibility: .swallowedByNotch)
        let strategies = plan(target: target, others: [], hasAXElement: true)
        #expect(strategies == [.syntheticClick(at: CGPoint(x: 720, y: 965.5)), .axPress])
    }
}

struct DragPlannerTests {

    private let geometry = MenuBarGeometry(
        screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        notchRect: CGRect(x: 663, y: 950, width: 185, height: 32),
        menuBarHeight: 33
    )

    private func bar(_ minX: CGFloat, _ width: CGFloat = 40) -> CGRect {
        CGRect(x: minX, y: 949, width: width, height: 33)
    }

    private func record(
        _ minX: CGFloat,
        _ width: CGFloat = 40,
        visibility: ItemVisibility = .visible,
        pid: Int32? = nil
    ) -> MenuBarItemRecord {
        MenuBarItemRecord(
            frame: bar(minX, width),
            visibility: visibility,
            identity: pid.map { ItemIdentity(pid: $0, bundleIdentifier: nil, appName: "App \($0)", axTitle: nil) }
        )
    }

    private let target = MenuBarItemRecord(
        frame: CGRect(x: 700, y: 949, width: 40, height: 33),
        visibility: .swallowedByNotch,
        identity: nil
    )

    @Test func testDestinationFullyVacatesTheNotchSide() {
        // Neighbor 40pt wide at x=900: destination centerX = 663 − 20 − 8 = 635.
        let dragPlan = DragPlanner.plan(
            target: target,
            allItems: [target, record(900, pid: 500)],
            ownFrames: [],
            geometry: geometry
        )
        #expect(dragPlan?.from == CGPoint(x: 920, y: 965.5))
        #expect(dragPlan?.to == CGPoint(x: 635, y: 965.5))
    }

    @Test func testNearestNeighborIsPicked() {
        let dragPlan = DragPlanner.plan(
            target: target,
            allItems: [target, record(1100, pid: 500), record(900, pid: 501), record(1000, pid: 502)],
            ownFrames: [],
            geometry: geometry
        )
        #expect(dragPlan?.neighborFrame.minX == 900)
    }

    @Test func testThirdPartyPreferredOverUnidentified() {
        let dragPlan = DragPlanner.plan(
            target: target,
            allItems: [target, record(900), record(1000, pid: 500)],
            ownFrames: [],
            geometry: geometry
        )
        #expect(dragPlan?.neighborFrame.minX == 1000)
    }

    @Test func testOwnFramesAndClockClusterAreExcluded() {
        let ownFrame = bar(900)
        let clock = record(1480, 30, pid: 600) // ends 2pt from the edge
        let dragPlan = DragPlanner.plan(
            target: target,
            allItems: [target, record(900, pid: 500), clock],
            ownFrames: [ownFrame],
            geometry: geometry
        )
        #expect(dragPlan == nil)
    }

    @Test func testSwallowedItemsAreNeverDragCandidates() {
        let dragPlan = DragPlanner.plan(
            target: target,
            allItems: [target, record(750, visibility: .swallowedByNotch, pid: 500)],
            ownFrames: [],
            geometry: geometry
        )
        #expect(dragPlan == nil)
    }

    @Test func testNoNotchMeansNoDragPlan() {
        let flat = MenuBarGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            notchRect: nil,
            menuBarHeight: 24
        )
        let dragPlan = DragPlanner.plan(
            target: target,
            allItems: [target, record(900, pid: 500)],
            ownFrames: [],
            geometry: flat
        )
        #expect(dragPlan == nil)
    }

    @Test func testNeighborThatCannotFullyVacateYieldsNil() {
        // Almost no room left of the notch: the clamp can't place the
        // 40pt neighbor fully past it (destination 28+20=48 > notch.minX 40).
        let crampedGeometry = MenuBarGeometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            notchRect: CGRect(x: 40, y: 950, width: 185, height: 32),
            menuBarHeight: 33
        )
        let crampedTarget = MenuBarItemRecord(
            frame: bar(60), visibility: .swallowedByNotch, identity: nil
        )
        let dragPlan = DragPlanner.plan(
            target: crampedTarget,
            allItems: [crampedTarget, record(300, pid: 500)],
            ownFrames: [],
            geometry: crampedGeometry
        )
        #expect(dragPlan == nil)
    }
}
