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

    public static func contains(
        _ point: CGPoint,
        toggleFrame: CGRect?,
        screenFrame: CGRect?
    ) -> Bool {
        guard let band = band(toggleFrame: toggleFrame, screenFrame: screenFrame) else {
            return false
        }
        return point.x >= band.minX && point.x < band.maxX
            && point.y >= band.minY && point.y < band.maxY
    }
}

/// Edge detector for a permission-free stream of pointer locations.
public struct MenuBarHoverTracker {

    public private(set) var isPointerInside = false

    public init() {}

    public mutating func update(
        enabled: Bool,
        buttonsDown: Bool,
        point: CGPoint,
        toggleFrame: CGRect?,
        screenFrame: CGRect?
    ) -> MenuBarHoverTransition? {
        guard enabled else {
            isPointerInside = false
            return nil
        }
        guard !buttonsDown else { return nil }

        let isInside = MenuBarHoverRegion.contains(
            point,
            toggleFrame: toggleFrame,
            screenFrame: screenFrame
        )
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
