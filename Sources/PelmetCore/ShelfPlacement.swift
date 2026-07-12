import CoreGraphics

/// Pure panel-frame math for the Shelf, in AppKit (bottom-left origin)
/// screen coordinates.
public enum ShelfPlacement {

    /// Where the Shelf panel goes: just below the menu bar band, centered on
    /// the toggle when its position is known, else on the notch, else on the
    /// screen — always clamped inside the screen with a margin.
    public static func panelFrame(
        panelSize: CGSize,
        anchorFrame: CGRect?,     // toggle button's window frame; nil if unknown/swallowed
        geometry: MenuBarGeometry,
        edgeMargin: CGFloat = 8,
        gap: CGFloat = 6
    ) -> CGRect {
        let screen = geometry.screenFrame
        let top = screen.maxY - geometry.menuBarHeight - gap

        let preferredCenterX = anchorFrame?.midX
            ?? geometry.notchRect?.midX
            ?? screen.midX

        var minX = preferredCenterX - panelSize.width / 2
        minX = max(minX, screen.minX + edgeMargin)
        minX = min(minX, screen.maxX - edgeMargin - panelSize.width)

        return CGRect(
            x: minX,
            y: top - panelSize.height,
            width: panelSize.width,
            height: panelSize.height
        )
    }
}
