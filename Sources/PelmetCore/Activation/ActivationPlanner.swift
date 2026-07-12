import CoreGraphics
import Foundation

/// A drag of one visible neighbor item leftward past the notch, so macOS
/// reflows the status area and the blocked target shifts into visible
/// space. Coordinates are AppKit screen coordinates.
public struct DragPlan: Equatable {
    /// The neighbor being dragged (its frame at planning time).
    public let neighborFrame: CGRect
    public let from: CGPoint
    public let to: CGPoint

    public init(neighborFrame: CGRect, from: CGPoint, to: CGPoint) {
        self.neighborFrame = neighborFrame
        self.from = from
        self.to = to
    }
}

/// One step the executor knows how to perform. Strategies run in planner
/// order; each click-ish step gets a verification window before the next
/// one runs.
public enum ActivationStrategy: Equatable {
    /// Target was pushed off-screen by Pelmet's own collapse: expand first,
    /// re-resolve, and re-plan. (Handled by the executor before any session
    /// starts — never reaches a session.)
    case expandCollapsedBar
    /// Warp-assisted synthetic click at a fixed point (the speculative
    /// in-place click for notch-swallowed items; the only step needed for
    /// visible ones).
    case syntheticClick(at: CGPoint)
    /// AXPress on the item's live AX element. Unreliable on many apps
    /// (menus collapse after ~1s) — verification requires persistence.
    case axPress
    /// Temporarily activate Finder so a frontmost app's wide menus don't
    /// overlap the slot the drag is about to expose.
    case appMenuClearance
    /// Cmd-drag a visible neighbor left of the notch to make room.
    case dragToExpose(DragPlan)
    /// After the reflow: click the target at its freshly re-resolved
    /// position (the executor computes the actual point).
    case clickTargetAfterReflow
}

/// Pure strategy planning from classifier facts. The executor interprets;
/// this decides.
public enum ActivationPlanner {

    public static func plan(
        target: MenuBarItemRecord,
        allItems: [MenuBarItemRecord],
        ownFrames: [CGRect],
        geometry: MenuBarGeometry,
        hasAXElement: Bool
    ) -> [ActivationStrategy] {
        switch target.visibility {
        case .suspectedGhost:
            return []
        case .offscreenLeft:
            return [.expandCollapsedBar]
        case .visible:
            return [.syntheticClick(at: center(of: target.frame))]
        case .swallowedByNotch:
            // MenuDown's proven order: speculative in-place click (the
            // window server discards notch-zone clicks "often, but not
            // always"), AXPress if we hold an element, then make room.
            var strategies: [ActivationStrategy] = [
                .syntheticClick(at: center(of: target.frame)),
            ]
            if hasAXElement {
                strategies.append(.axPress)
            }
            if let dragPlan = DragPlanner.plan(
                target: target, allItems: allItems, ownFrames: ownFrames, geometry: geometry
            ) {
                strategies.append(.appMenuClearance)
                strategies.append(.dragToExpose(dragPlan))
                strategies.append(.clickTargetAfterReflow)
            }
            return strategies
        }
    }

    static func center(of frame: CGRect) -> CGPoint {
        CGPoint(x: frame.midX, y: frame.midY)
    }
}

public enum DragPlanner {

    /// Gap kept between the dragged neighbor and the notch / screen edge.
    public static let margin: CGFloat = 8
    /// Frames ending this close to the right screen edge are the clock
    /// cluster — never drag those.
    public static let clockClusterMargin: CGFloat = 8

    /// Picks the visible neighbor nearest to the notch (right side) and
    /// computes the leftward drag that fully vacates its slot. Returns nil
    /// when nothing can safely move — the caller fails with
    /// `.noRoomToExpose` instead of guessing.
    public static func plan(
        target: MenuBarItemRecord,
        allItems: [MenuBarItemRecord],
        ownFrames: [CGRect],
        geometry: MenuBarGeometry
    ) -> DragPlan? {
        guard let notch = geometry.notchRect else { return nil }

        let candidates = allItems.filter { item in
            item.visibility == .visible
                && item.id != target.id
                && item.frame.minX > notch.maxX
                && item.frame.maxX < geometry.screenFrame.maxX - clockClusterMargin
                && !ownFrames.contains { own in
                    abs(own.midX - item.frame.midX) < 2
                }
        }

        // Nearest to the notch; when identity is known, prefer third-party
        // items (dragging aggregated system items is the fragile case).
        let neighbor = candidates.min { a, b in
            let aOwned = a.identity != nil, bOwned = b.identity != nil
            if aOwned != bOwned { return aOwned }
            return a.frame.minX < b.frame.minX
        }
        guard let neighbor else { return nil }

        let width = neighbor.frame.width
        var destinationX = notch.minX - width / 2 - margin
        destinationX = max(destinationX, geometry.screenFrame.minX + width / 2 + margin)
        // If clamping couldn't put the neighbor fully left of the notch,
        // the left side is packed too — moving it wouldn't free the slot.
        guard destinationX + width / 2 <= notch.minX else { return nil }

        let y = neighbor.frame.midY
        return DragPlan(
            neighborFrame: neighbor.frame,
            from: CGPoint(x: neighbor.frame.midX, y: y),
            to: CGPoint(x: destinationX, y: y)
        )
    }
}
