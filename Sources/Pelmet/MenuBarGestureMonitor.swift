import AppKit
import os
import PelmetCore

/// Opt-in reveal and rehide gestures from permission-free mouse and scroll
/// events: a scroll or an empty-bar click near Pelmet's icons reveals them, and
/// a click outside the menu bar hides them again. Global monitors for mouse and
/// scroll events need no Accessibility permission (only key events do), the
/// same as show on hover. The decisions live in `MenuBarGesturePolicy`.
final class MenuBarGestureMonitor {

    struct Context {
        let isCollapsed: Bool
        let toggleFrame: CGRect?
        let revealBand: CGRect?
        /// Pelmet's own status items, so a click on the collapsed divider
        /// counts as empty space rather than as another app's item.
        let ownItemFrames: [CGRect]
        /// False on macOS 27's single-window bar: no item frames are readable
        /// there, so a click near the icons can't be told from a click on one.
        let canHitTestItems: Bool
    }

    var contextProvider: (() -> Context?)?
    var onReveal: (() -> Void)?
    var onHide: (() -> Void)?

    private let logger = Logger(
        subsystem: "com.ismatbabirli.Pelmet",
        category: "MenuBarGestureMonitor"
    )
    private var monitors: [Any] = []

    /// Installs only the monitors the current settings need, and none at all
    /// when every gesture is off.
    func configure(scroll: Bool, barClick: Bool, outsideClick: Bool) {
        stop()
        var mask: NSEvent.EventTypeMask = []
        if scroll {
            mask.insert(.scrollWheel)
        }
        if barClick || outsideClick {
            mask.formUnion([.leftMouseDown, .rightMouseDown])
        }
        guard !mask.isEmpty else { return }

        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handle(event, inPelmet: false)
        }) {
            monitors.append(global)
        } else {
            logger.error("Unable to install the global gesture monitor")
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handle(event, inPelmet: true)
            return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }

    /// `inPelmet` marks an event delivered to Pelmet itself: its status items
    /// or one of its windows (Settings, the Shelf, a tip).
    private func handle(_ event: NSEvent, inPelmet: Bool) {
        guard let context = contextProvider?() else { return }
        let point = NSEvent.mouseLocation

        switch event.type {
        case .scrollWheel:
            // A trackpad swipe starts with .began; a mouse wheel has no phases.
            let isGestureStart = event.phase.contains(.began)
                || (event.phase.isEmpty && event.momentumPhase.isEmpty)
            if MenuBarGesturePolicy.revealsOnScroll(
                enabled: Preferences.showOnScroll,
                isCollapsed: context.isCollapsed,
                isGestureStart: isGestureStart,
                point: point,
                revealBand: context.revealBand
            ) {
                onReveal?()
            }

        case .leftMouseDown, .rightMouseDown:
            if context.isCollapsed {
                // In Pelmet too: a click on the collapsed divider is empty space.
                handleBarClick(event, at: point, context: context)
            } else if !inPelmet {
                // A click in Pelmet's own UI, the Shelf above all, is never an
                // outside click: collapsing would close the Shelf under it.
                handleOutsideClick(at: point)
            }

        default:
            break
        }
    }

    private func handleBarClick(_ event: NSEvent, at point: CGPoint, context: Context) {
        // Cheap checks first: the window list is read only for a click that
        // could reveal.
        guard event.type == .leftMouseDown,
              Preferences.showOnBarClick,
              context.canHitTestItems,
              let band = context.revealBand,
              MenuBarHoverRegion.contains(point, in: band)
        else { return }

        if MenuBarGesturePolicy.revealsOnBarClick(
            enabled: true,
            isCollapsed: true,
            point: point,
            revealBand: band,
            toggleFrame: context.toggleFrame,
            hitsOtherStatusItem: hitsOtherStatusItem(point, ownItemFrames: context.ownItemFrames)
        ) {
            onReveal?()
        }
    }

    private func handleOutsideClick(at point: CGPoint) {
        guard Preferences.hideOnOutsideClick else { return }
        let strips = NSScreen.screens.map { screen in
            MenuBarGesturePolicy.menuBarStrip(
                screenFrame: screen.frame,
                visibleFrame: screen.visibleFrame,
                fallbackHeight: NSStatusBar.system.thickness
            )
        }
        // Inside a menu bar it is never an outside click; skip the window read.
        guard !strips.contains(where: { MenuBarHoverRegion.contains(point, in: $0) }) else { return }

        if MenuBarGesturePolicy.hidesOnOutsideClick(
            enabled: true,
            isCollapsed: false,
            point: point,
            menuBarStrips: strips,
            isMenuOpen: WindowListSource.isAnyMenuOpen(),
            isPelmetWindowOpen: UIActivityTracker.shared.openSurfaces > 0
        ) {
            onHide?()
        }
    }

    /// Another app's status item under the point. Pelmet's own windows are
    /// matched by frame as well as by owner, because on macOS 26 Control
    /// Center owns every status-item window. An unreadable window list counts
    /// as a hit, so an unknown click never reveals.
    private func hitsOtherStatusItem(_ point: CGPoint, ownItemFrames: [CGRect]) -> Bool {
        guard let windows = WindowListSource.statusItemWindows() else { return true }
        let ownPID = Int32(ProcessInfo.processInfo.processIdentifier)
        return windows.contains { window in
            window.frame.contains(point)
                && window.ownerPID != ownPID
                && !ownItemFrames.contains { Self.isSameFrame($0, window.frame) }
        }
    }

    private static func isSameFrame(_ a: CGRect, _ b: CGRect) -> Bool {
        let tolerance: CGFloat = 2
        return abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }
}
