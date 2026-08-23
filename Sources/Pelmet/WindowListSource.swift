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

    /// Top-center overlay candidates using the same permission-free metadata
    /// as status-item discovery. App identity is resolved locally from the
    /// owning PID and never leaves the Mac.
    static func softwareIslandWindows() -> [SoftwareIslandDetection] {
        guard
            let primary = NSScreen.screens.first,
            let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]
        else { return [] }

        let primaryMaxY = primary.frame.maxY
        let ownPID = Int32(ProcessInfo.processInfo.processIdentifier)

        return list.compactMap { info in
            guard
                let level = info[kCGWindowLayer as String] as? Int,
                level > statusItemWindowLevel,
                info[kCGWindowIsOnscreen as String] as? Bool == true,
                let pid = info[kCGWindowOwnerPID as String] as? Int32,
                pid != ownPID,
                let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                let x = bounds["X"], let y = bounds["Y"],
                let width = bounds["Width"], let height = bounds["Height"],
                width > 0, height > 0,
                let app = NSRunningApplication(processIdentifier: pid),
                let bundleIdentifier = app.bundleIdentifier
            else { return nil }

            let frame = CGRect(
                x: x,
                y: primaryMaxY - y - height,
                width: width,
                height: height
            )
            guard let screen = NSScreen.screens.first(where: { candidate in
                frame.intersects(candidate.frame)
                    && abs(frame.maxY - candidate.frame.maxY)
                        <= SoftwareIslandCandidateClassifier.topEdgeTolerance
            }) else { return nil }

            let isSystemOwner = bundleIdentifier.hasPrefix("com.apple.")
            let observation = SoftwareIslandWindowObservation(
                frame: frame,
                layer: level,
                bundleIdentifier: bundleIdentifier,
                isAccessoryApplication: app.activationPolicy == .accessory,
                isSystemOwner: isSystemOwner
            )
            guard SoftwareIslandCandidateClassifier.isCandidate(
                observation,
                screenFrame: screen.frame,
                menuBarHeight: max(NSStatusBar.system.thickness, screen.safeAreaInsets.top)
            ) else { return nil }

            return SoftwareIslandDetection(
                bundleIdentifier: bundleIdentifier,
                displayName: app.localizedName ?? bundleIdentifier,
                screenFrame: screen.frame,
                outerWindowFrame: observation.frame
            )
        }
    }
}
