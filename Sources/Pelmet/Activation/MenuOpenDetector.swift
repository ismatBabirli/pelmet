import AppKit
import PelmetCore

/// Permission-free verification that an Accessibility action opened something:
/// watch for a new menu/popover-level window near the target. Also observes
/// when that menu closes so auto-rehide can resume. Uses only CGWindowList
/// bounds/level metadata — no Screen Recording, no titles.
final class MenuOpenDetector {

    /// Window layers a menu or status popover lives at. Menus sit at/above
    /// the status-item level (25); include a generous band up through the
    /// pop-up menu level (101) and a little beyond.
    private static let menuLayerRange = 20...200
    private static let horizontalTolerance: CGFloat = 250
    private static let topTolerance: CGFloat = 80

    /// Window IDs present at the menu level before the Accessibility action.
    func baselineWindowIDs() -> Set<Int> {
        Set(menuWindows().map(\.id))
    }

    /// A new menu-level window near `targetPoint` (AppKit coords) that wasn't
    /// in `baseline`. Status-item menus drop down from the bar, so the window's
    /// top edge sits just under it and its horizontal span overlaps the item.
    func newMenuWindowID(near targetPoint: CGPoint, baseline: Set<Int>) -> Int? {
        let screen = NSScreen.screens.first { $0.frame.contains(targetPoint) } ?? NSScreen.main
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        let menuBarBottom = (screen?.frame.maxY ?? primaryMaxY) - (screen?.safeAreaInsets.top ?? 24)

        for window in menuWindows() where !baseline.contains(window.id) {
            let appKit = ScreenCoordinates.appKitRect(fromCG: window.bounds, primaryMaxY: primaryMaxY)
            let nearX = appKit.minX - Self.horizontalTolerance <= targetPoint.x
                && targetPoint.x <= appKit.maxX + Self.horizontalTolerance
            // A dropped menu's top edge is within a small band of the bar.
            let nearTop = abs(appKit.maxY - menuBarBottom) <= Self.topTolerance
            if nearX && nearTop { return window.id }
        }
        return nil
    }

    /// Any menu-level window beyond `baseline` — the user may be browsing a
    /// menu we opened, or a submenu that replaced its window. Robust to that
    /// churn, unlike single-ID tracking; deliberately X-agnostic, since
    /// submenus extend far from the item.
    func hasNewMenuWindows(baseline: Set<Int>) -> Bool {
        menuWindows().contains { !baseline.contains($0.id) }
    }

    // MARK: - Window snapshot

    private struct MenuWindow {
        let id: Int
        let bounds: CGRect
    }

    private func menuWindows() -> [MenuWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        return list.compactMap { info in
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  Self.menuLayerRange.contains(layer),
                  let id = info[kCGWindowNumber as String] as? Int,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let width = bounds["Width"], let height = bounds["Height"]
            else { return nil }
            return MenuWindow(id: id, bounds: CGRect(x: x, y: y, width: width, height: height))
        }
    }
}
