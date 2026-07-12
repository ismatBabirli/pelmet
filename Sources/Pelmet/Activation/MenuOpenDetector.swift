import AppKit
import PelmetCore

/// Permission-free verification that a click opened something: watch for a
/// new window at the menu/popover level near the click, appearing after we
/// posted the click. Also detects that menu closing (gates the restore
/// drag). Uses only CGWindowList bounds/level metadata — no Screen
/// Recording, no titles.
final class MenuOpenDetector {

    /// Window layers a menu or status popover lives at. Menus sit at/above
    /// the status-item level (25); include a generous band up through the
    /// pop-up menu level (101) and a little beyond.
    private static let menuLayerRange = 20...200
    private static let horizontalTolerance: CGFloat = 250
    private static let topTolerance: CGFloat = 80

    /// Window IDs present at the menu level before the click.
    func baselineWindowIDs() -> Set<Int> {
        Set(menuWindows().map(\.id))
    }

    /// A new menu-level window near `clickPoint` (AppKit coords) that wasn't
    /// in `baseline` — i.e. our click opened a menu. Status-item menus drop
    /// down from the bar, so the window's top edge sits just under it and
    /// its horizontal span overlaps the clicked item.
    func newMenuWindowID(near clickPoint: CGPoint, baseline: Set<Int>) -> Int? {
        let screen = NSScreen.screens.first { $0.frame.contains(clickPoint) } ?? NSScreen.main
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        let menuBarBottom = (screen?.frame.maxY ?? primaryMaxY) - (screen?.safeAreaInsets.top ?? 24)

        for window in menuWindows() where !baseline.contains(window.id) {
            let appKit = ScreenCoordinates.appKitRect(fromCG: window.bounds, primaryMaxY: primaryMaxY)
            let nearX = appKit.minX - Self.horizontalTolerance <= clickPoint.x
                && clickPoint.x <= appKit.maxX + Self.horizontalTolerance
            // A dropped menu's top edge is within a small band of the bar.
            let nearTop = abs(appKit.maxY - menuBarBottom) <= Self.topTolerance
            if nearX && nearTop { return window.id }
        }
        return nil
    }

    /// Whether a given window ID is still present (menu still open).
    func isWindowPresent(_ id: Int) -> Bool {
        menuWindows().contains { $0.id == id }
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
