import AppKit

/// The only file that talks to the window server. Everything it uses is
/// public API that requires no permission, triggers no TCC prompt, and never
/// lights the screen-capture privacy indicator: `CGWindowListCopyWindowInfo`
/// returns window bounds/level metadata freely (only window *titles* are
/// gated behind Screen Recording, and Pelmet never reads those).
enum WindowListSource {

    /// Level 25 is the status-item window level (`NSWindow.Level.statusBar`).
    private static let statusItemWindowLevel = 25

    /// Frames of every status-item window on all displays, converted to
    /// AppKit screen coordinates (bottom-left origin). Includes duplicates
    /// and Pelmet's own items — `MenuBarLayoutClassifier` filters both.
    static func statusItemWindowFrames() -> [CGRect] {
        guard
            let primary = NSScreen.screens.first,
            let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]
        else { return [] }

        // CG global coordinates are top-left-origin; x is shared, y flips
        // around the primary screen's top edge.
        let primaryMaxY = primary.frame.maxY

        return list.compactMap { info in
            guard
                let level = info[kCGWindowLayer as String] as? Int,
                level == statusItemWindowLevel,
                let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                let x = bounds["X"], let y = bounds["Y"],
                let width = bounds["Width"], let height = bounds["Height"]
            else { return nil }
            return CGRect(x: x, y: primaryMaxY - y - height, width: width, height: height)
        }
    }
}
