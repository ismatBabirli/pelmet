import CoreGraphics

/// Conversions between the two global coordinate systems Pelmet straddles:
/// CoreGraphics/window-server coordinates (top-left origin, y grows down)
/// and AppKit screen coordinates (bottom-left origin, y grows up). Both
/// flips pivot on the primary screen's top edge (`primaryMaxY` in AppKit
/// coordinates, which equals the CG origin's y).
public enum ScreenCoordinates {

    public static func appKitRect(fromCG rect: CGRect, primaryMaxY: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryMaxY - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    public static func cgRect(fromAppKit rect: CGRect, primaryMaxY: CGFloat) -> CGRect {
        // The flip is its own inverse.
        appKitRect(fromCG: rect, primaryMaxY: primaryMaxY)
    }

    public static func appKitPoint(fromCG point: CGPoint, primaryMaxY: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryMaxY - point.y)
    }

    public static func cgPoint(fromAppKit point: CGPoint, primaryMaxY: CGFloat) -> CGPoint {
        appKitPoint(fromCG: point, primaryMaxY: primaryMaxY)
    }
}
