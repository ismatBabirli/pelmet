import CoreGraphics

/// A pointer transition across the menu bar region that currently hosts
/// Pelmet's toggle.
public enum MenuBarHoverTransition: Equatable {
    case entered
    case exited
}

/// Pure geometry for turning Pelmet's live status-item frame into the full
/// horizontal menu bar region on that display.
public enum MenuBarHoverRegion {

    public static func band(toggleFrame: CGRect?, screenFrame: CGRect?) -> CGRect? {
        guard let toggleFrame, let screenFrame,
              toggleFrame.width > 0, toggleFrame.height > 0,
              screenFrame.width > 0, screenFrame.height > 0
        else { return nil }

        let minY = max(toggleFrame.minY, screenFrame.minY)
        let maxY = min(toggleFrame.maxY, screenFrame.maxY)
        guard maxY > minY, toggleFrame.maxX > screenFrame.minX,
              toggleFrame.minX < screenFrame.maxX
        else { return nil }

        return CGRect(
            x: screenFrame.minX,
            y: minY,
            width: screenFrame.width,
            height: maxY - minY
        )
    }

    /// The stretch of that band that starts a reveal: from where status items
    /// begin (the notch's right edge, or the middle of a display without one)
    /// to the toggle's right edge. App menus on the left stay out of it, so
    /// reaching for File or Edit never reveals anything.
    public static func revealBand(
        toggleFrame: CGRect?,
        screenFrame: CGRect?,
        statusAreaMinX: CGFloat?
    ) -> CGRect? {
        guard let band = band(toggleFrame: toggleFrame, screenFrame: screenFrame),
              let toggleFrame
        else { return nil }

        // A toggle pushed left of that point (a very crowded bar) still
        // reveals from its own left edge.
        let start = min(statusAreaMinX ?? band.midX, toggleFrame.minX)
        let minX = max(band.minX, start)
        let maxX = min(band.maxX, toggleFrame.maxX)
        guard maxX > minX else { return nil }
        return CGRect(x: minX, y: band.minY, width: maxX - minX, height: band.height)
    }

    public static func contains(
        _ point: CGPoint,
        toggleFrame: CGRect?,
        screenFrame: CGRect?
    ) -> Bool {
        guard let band = band(toggleFrame: toggleFrame, screenFrame: screenFrame) else {
            return false
        }
        return contains(point, in: band)
    }

    /// Half-open on the far edges, so adjacent bands never both claim a point.
    public static func contains(_ point: CGPoint, in band: CGRect) -> Bool {
        point.x >= band.minX && point.x < band.maxX
            && point.y >= band.minY && point.y < band.maxY
    }
}

/// Edge detector for a permission-free stream of pointer locations.
public struct MenuBarHoverTracker {

    public private(set) var isPointerInside = false

    public init() {}

    /// One region for entering and staying: the full menu bar band.
    public mutating func update(
        enabled: Bool,
        buttonsDown: Bool,
        point: CGPoint,
        toggleFrame: CGRect?,
        screenFrame: CGRect?
    ) -> MenuBarHoverTransition? {
        let band = MenuBarHoverRegion.band(toggleFrame: toggleFrame, screenFrame: screenFrame)
        return update(
            enabled: enabled,
            buttonsDown: buttonsDown,
            point: point,
            revealBand: band,
            retainBand: band
        )
    }

    /// Two regions: the pointer has to enter `revealBand` to count as inside,
    /// then stays inside anywhere in `retainBand`. Moving across the revealed
    /// icons or the rest of the bar does not end the hover.
    public mutating func update(
        enabled: Bool,
        buttonsDown: Bool,
        point: CGPoint,
        revealBand: CGRect?,
        retainBand: CGRect?
    ) -> MenuBarHoverTransition? {
        guard enabled else {
            isPointerInside = false
            return nil
        }
        guard !buttonsDown else { return nil }

        let region = isPointerInside ? retainBand : revealBand
        let isInside = region.map { MenuBarHoverRegion.contains(point, in: $0) } ?? false
        guard isInside != isPointerInside else { return nil }
        isPointerInside = isInside
        return isInside ? .entered : .exited
    }

    public mutating func reset() {
        isPointerInside = false
    }
}

/// Pure decisions for coordinating hover transitions with the existing
/// expand and auto-rehide behavior.
public enum MenuBarHoverPolicy {

    public struct Decision: Equatable {
        public let cancelRehide: Bool
        public let reveal: Bool
        public let scheduleRehide: Bool

        public init(cancelRehide: Bool, reveal: Bool, scheduleRehide: Bool) {
            self.cancelRehide = cancelRehide
            self.reveal = reveal
            self.scheduleRehide = scheduleRehide
        }
    }

    public static func decide(
        transition: MenuBarHoverTransition,
        isCollapsed: Bool,
        autoRehide: Bool
    ) -> Decision {
        switch transition {
        case .entered:
            return Decision(
                cancelRehide: true,
                reveal: isCollapsed,
                scheduleRehide: false
            )
        case .exited:
            return Decision(
                cancelRehide: false,
                reveal: false,
                scheduleRehide: !isCollapsed && autoRehide
            )
        }
    }
}
