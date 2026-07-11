import CoreGraphics
import Foundation

/// Pure geometry: given raw menu-bar-item window frames and the notch rect,
/// decide which items macOS is silently refusing to draw.
///
/// Everything here is derived from empirical probes on macOS 26.5 (Tahoe),
/// where the only reliable signal is geometry:
///  - swallowed items keep window frames that continue under the notch and
///    past the left screen edge, laid out as if the notch didn't exist;
///  - `kCGWindowIsOnscreen` is absent without Screen Recording permission;
///  - `NSWindow.occlusionState` reports "occluded" even for visible items;
///  - each item can be backed by more than one window: an exact-frame
///    duplicate (Control Center mirror) and, during layout churn, a stale
///    ghost offset by ~10–20pt — hence overlap-clustering, not exact dedupe;
///  - non-item windows can live at the status-item window level (observed:
///    a 450pt-wide clipboard-manager panel) — hence the width sanity cap;
///  - when items MOVE (notably: Pelmet's own collapse/expand relocating the
///    whole managed section), one window of a twin pair can linger at the
///    old position for minutes with no distinguishing field (alpha, memory,
///    store type all identical to live windows). These stale twins park in
///    two signature zones: exactly x == 0 (the item-birth position) and past
///    the left screen edge (old collapsed-layout positions). Both zones are
///    excluded from the swallowed count — genuine overflow only reaches
///    negative x when 15+ icons deep, at which point the on-screen-zone
///    count is still directionally right.
public enum ItemVisibility: Equatable {
    /// Drawn in the menu bar.
    case visible
    /// Frame in or left of the notch while the bar is full — macOS gives it
    /// no space and no indication. The user cannot see or reach it.
    case swallowedByNotch
    /// Pushed past the left screen edge by Pelmet's own inflated separator —
    /// expected and intentional while collapsed.
    case offscreenLeft
    /// Almost certainly a stale twin window, not a real icon (see below) —
    /// never counted.
    case suspectedGhost
}

public struct ClassifiedItem: Equatable {
    public let frame: CGRect
    public let visibility: ItemVisibility

    public init(frame: CGRect, visibility: ItemVisibility) {
        self.frame = frame
        self.visibility = visibility
    }
}

public enum SeparatorHealth: Equatable {
    case visible
    case swallowed
    /// Collapsed (glyph hidden by design) or measurement unavailable.
    case unknown
}

/// Inputs are all in AppKit screen coordinates (bottom-left origin).
public struct MenuBarGeometry: Equatable {
    public let screenFrame: CGRect
    /// nil on screens without a camera housing.
    public let notchRect: CGRect?
    /// Height of the menu bar band at the top of `screenFrame`.
    public let menuBarHeight: CGFloat

    public init(screenFrame: CGRect, notchRect: CGRect?, menuBarHeight: CGFloat) {
        self.screenFrame = screenFrame
        self.notchRect = notchRect
        self.menuBarHeight = menuBarHeight
    }

    /// The horizontal strip status items live in on this screen.
    public var band: CGRect {
        CGRect(
            x: screenFrame.minX - 10_000, // pushed items keep band-height frames far past the edge
            y: screenFrame.maxY - menuBarHeight - 2,
            width: screenFrame.width + 20_000,
            height: menuBarHeight + 4
        )
    }
}

public struct LayoutClassification: Equatable {
    public let items: [ClassifiedItem]
    public let separatorHealth: SeparatorHealth
    public let toggleVisible: Bool

    public var swallowedCount: Int {
        items.filter { $0.visibility == .swallowedByNotch }.count
    }

    public var offscreenLeftCount: Int {
        items.filter { $0.visibility == .offscreenLeft }.count
    }

    /// The fields user-facing state hangs off; two consecutive measurements
    /// must agree on this before the UI reacts (transient-noise guard).
    public struct Digest: Equatable {
        public let swallowedCount: Int
        public let separatorHealth: SeparatorHealth
        public let toggleVisible: Bool
    }

    public var digest: Digest {
        Digest(swallowedCount: swallowedCount, separatorHealth: separatorHealth, toggleVisible: toggleVisible)
    }
}

public enum MenuBarLayoutClassifier {

    /// Wider than any plausible status item; filters panels that share the
    /// status window level (and Pelmet's own inflated separator, if its
    /// frames ever slip past exclusion).
    public static let maxPlausibleItemWidth: CGFloat = 300

    /// Two frames whose x-ranges overlap by more than this fraction of the
    /// narrower one are the same item (mirror or mid-layout ghost).
    static let overlapDedupeFraction: CGFloat = 0.4

    static let frameMatchTolerance: CGFloat = 1.5

    public static func classify(
        rawItemFrames: [CGRect],
        ownSeparatorFrame: CGRect?,
        ownToggleFrame: CGRect?,
        isCollapsed: Bool,
        geometry: MenuBarGeometry
    ) -> LayoutClassification {
        let band = geometry.band
        let ownFrames = [ownSeparatorFrame, ownToggleFrame].compactMap { $0 }

        let candidates = rawItemFrames.filter { frame in
            band.contains(CGPoint(x: frame.midX, y: frame.midY))
                && frame.width > 4 && frame.width <= maxPlausibleItemWidth
                && !ownFrames.contains(where: { matches($0, frame) })
        }

        let deduped = dedupe(candidates)

        let items = deduped.map { frame in
            ClassifiedItem(
                frame: frame,
                visibility: visibility(
                    of: frame,
                    isCollapsed: isCollapsed,
                    separatorFrame: ownSeparatorFrame,
                    geometry: geometry
                )
            )
        }

        let separatorHealth: SeparatorHealth
        if isCollapsed {
            separatorHealth = .unknown
        } else if let sep = ownSeparatorFrame {
            separatorHealth = isSwallowed(sep, geometry: geometry) ? .swallowed : .visible
        } else {
            separatorHealth = .unknown
        }

        let toggleVisible: Bool
        if let toggle = ownToggleFrame {
            toggleVisible = !isSwallowed(toggle, geometry: geometry)
                && toggle.maxX <= geometry.screenFrame.maxX + frameMatchTolerance
        } else {
            toggleVisible = false
        }

        return LayoutClassification(
            items: items,
            separatorHealth: separatorHealth,
            toggleVisible: toggleVisible
        )
    }

    // MARK: - Internals

    private static func visibility(
        of frame: CGRect,
        isCollapsed: Bool,
        separatorFrame: CGRect?,
        geometry: MenuBarGeometry
    ) -> ItemVisibility {
        if isCollapsed, let sep = separatorFrame, frame.maxX <= sep.minX + 2 {
            return .offscreenLeft
        }
        if abs(frame.minX - 0) < 0.5 {
            // Exactly x == 0 is the item-birth position — a stale twin left
            // behind when an item was created and immediately moved. Real
            // packed items land at arbitrary offsets, not exactly 0.
            return .suspectedGhost
        }
        if frame.maxX <= geometry.screenFrame.minX {
            // Past the left edge. While collapsed that's our own doing even
            // when the separator frame was unreadable; while expanded these
            // are overwhelmingly stale twins parked at old collapsed-layout
            // positions (verified: an ordinary expand leaves the previous
            // collapse's mirror windows lingering there).
            return isCollapsed ? .offscreenLeft : .suspectedGhost
        }
        if isSwallowed(frame, geometry: geometry) {
            return .swallowedByNotch
        }
        return .visible
    }

    private static func isSwallowed(_ frame: CGRect, geometry: MenuBarGeometry) -> Bool {
        guard let notch = geometry.notchRect else { return false }
        // Items never render in or left of the notch; a band frame there is
        // invisible. Small inset absorbs frames that merely kiss the edge.
        return frame.intersects(notch.insetBy(dx: 2, dy: 0)) || frame.maxX <= notch.minX + 2
    }

    private static func matches(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= frameMatchTolerance && abs(a.width - b.width) <= frameMatchTolerance
    }

    /// Cluster frames whose x-ranges substantially overlap and keep one per
    /// cluster. Adjacent distinct items never overlap; mirrors overlap fully
    /// and mid-layout ghosts by half or more.
    static func dedupe(_ frames: [CGRect]) -> [CGRect] {
        let sorted = frames.sorted { $0.minX < $1.minX }
        var result: [CGRect] = []
        for frame in sorted {
            if let last = result.last {
                let overlap = min(last.maxX, frame.maxX) - max(last.minX, frame.minX)
                let narrower = min(last.width, frame.width)
                if overlap > narrower * overlapDedupeFraction {
                    continue
                }
            }
            result.append(frame)
        }
        return result
    }
}
