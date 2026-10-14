import CoreGraphics

/// Pure decisions for the opt-in reveal and rehide gestures. The monitors that
/// feed them watch permission-free mouse and scroll events only.
public enum MenuBarGesturePolicy {

    /// A scroll that starts inside the reveal band shows hidden icons. Only the
    /// start of a gesture counts: the rest of a swipe, momentum included,
    /// belongs to the same gesture.
    public static func revealsOnScroll(
        enabled: Bool,
        isCollapsed: Bool,
        isGestureStart: Bool,
        point: CGPoint,
        revealBand: CGRect?
    ) -> Bool {
        guard enabled, isCollapsed, isGestureStart, let revealBand else { return false }
        return MenuBarHoverRegion.contains(point, in: revealBand)
    }

    /// A click on empty menu bar space inside the reveal band shows hidden
    /// icons. A click on another app's status item, or on Pelmet's own toggle,
    /// belongs to that item.
    public static func revealsOnBarClick(
        enabled: Bool,
        isCollapsed: Bool,
        point: CGPoint,
        revealBand: CGRect?,
        toggleFrame: CGRect?,
        hitsOtherStatusItem: Bool
    ) -> Bool {
        guard enabled, isCollapsed, !hitsOtherStatusItem, let revealBand else { return false }
        if let toggleFrame, MenuBarHoverRegion.contains(point, in: toggleFrame) {
            return false
        }
        return MenuBarHoverRegion.contains(point, in: revealBand)
    }

    /// A click outside every display's menu bar hides revealed icons again,
    /// unless a menu is open (the click is choosing from it or dismissing it)
    /// or one of Pelmet's own windows is (Settings, the Shelf, a tip).
    public static func hidesOnOutsideClick(
        enabled: Bool,
        isCollapsed: Bool,
        point: CGPoint,
        menuBarStrips: [CGRect],
        isMenuOpen: Bool,
        isPelmetWindowOpen: Bool
    ) -> Bool {
        guard enabled, !isCollapsed, !isMenuOpen, !isPelmetWindowOpen else { return false }
        return !menuBarStrips.contains { MenuBarHoverRegion.contains(point, in: $0) }
    }

    /// The menu bar's strip along the top of a display. A hidden menu bar (full
    /// screen, or "automatically hide") leaves no gap above the visible frame,
    /// so the system bar thickness stands in for it.
    public static func menuBarStrip(
        screenFrame: CGRect,
        visibleFrame: CGRect,
        fallbackHeight: CGFloat
    ) -> CGRect {
        let gap = screenFrame.maxY - visibleFrame.maxY
        let height = gap > 0 ? gap : fallbackHeight
        return CGRect(
            x: screenFrame.minX,
            y: screenFrame.maxY - height,
            width: screenFrame.width,
            height: height
        )
    }
}
