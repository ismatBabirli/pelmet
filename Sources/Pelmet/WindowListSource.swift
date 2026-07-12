import AppKit
import PelmetCore

/// The only file that talks to the window server. Everything it uses is
/// public API that requires no permission, triggers no TCC prompt, and never
/// lights the screen-capture privacy indicator: `CGWindowListCopyWindowInfo`
/// returns window bounds/level/owner metadata freely (only window *titles*
/// are gated behind Screen Recording, and Pelmet never reads those —
/// `kCGWindowOwnerPID` is in the same free metadata tier as bounds).
enum WindowListSource {

    /// Level 25 is the status-item window level (`NSWindow.Level.statusBar`).
    private static let statusItemWindowLevel = 25

    /// Every status-item window on all displays, converted to AppKit screen
    /// coordinates (bottom-left origin), with its owning process where the
    /// window server reports one. Includes duplicates and Pelmet's own items
    /// — `MenuBarLayoutClassifier` filters both.
    ///
    /// Ownership caveat: on macOS 26 (Tahoe) Control Center re-parents
    /// third-party status-item windows, so `ownerPID` is Control Center's
    /// for all of them. Consumers must treat Control-Center-owned frames as
    /// "owner unknown" rather than trusting the PID.
    static func statusItemWindows() -> [RawStatusWindow] {
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
            return RawStatusWindow(
                frame: CGRect(x: x, y: primaryMaxY - y - height, width: width, height: height),
                ownerPID: info[kCGWindowOwnerPID as String] as? Int32
            )
        }
    }
}
