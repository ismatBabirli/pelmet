import CoreGraphics

/// Pure placement math for the onboarding tip popovers, in AppKit
/// (bottom-left origin) screen coordinates.
///
/// macOS 26 can place a status-item popover one popover-height below its
/// anchor, arrow pointing at the desktop. The AppKit side detects that by
/// comparing the popover window's frame against the anchor's real screen
/// rect and asks this type for the corrected frame.
public enum TipPlacement {

    /// nil when the placement is sane (leave AppKit alone). Otherwise the
    /// frame the popover window should move to: top edge flush with the
    /// anchor's bottom edge, recentered on the anchor only when the window
    /// does not even cover it horizontally — AppKit legitimately slides the
    /// bubble sideways at screen edges while the arrow stays on the anchor,
    /// so a tight midX comparison would misfire — and clamped inside the
    /// screen with a margin.
    public static func correctedFrame(
        popoverFrame: CGRect,
        anchorRect: CGRect,
        screenFrame: CGRect,
        yTolerance: CGFloat = 16,
        xSlack: CGFloat = 8,
        edgeMargin: CGFloat = 8
    ) -> CGRect? {
        let yOK = abs(popoverFrame.maxY - anchorRect.minY) <= yTolerance
        let coversAnchorX = popoverFrame.minX - xSlack <= anchorRect.midX
            && anchorRect.midX <= popoverFrame.maxX + xSlack
        if yOK && coversAnchorX { return nil }

        var frame = popoverFrame
        frame.origin.y = anchorRect.minY - frame.height
        if !coversAnchorX {
            var x = anchorRect.midX - frame.width / 2
            x = max(x, screenFrame.minX + edgeMargin)
            x = min(x, screenFrame.maxX - edgeMargin - frame.width)
            frame.origin.x = x
        }
        return frame
    }
}
