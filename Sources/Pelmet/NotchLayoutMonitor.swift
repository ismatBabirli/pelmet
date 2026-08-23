import AppKit
import PelmetCore

/// Watches menu bar layout and reports, with zero permissions, how many
/// icons are hidden by a physical notch or software island, plus whether Pelmet's own
/// divider and toggle are visible.
///
/// Event-driven only (no polling): measurements run after expand/collapse
/// settles, on screen-parameter changes, and on workspace events that can
/// reflow the bar. A classification must repeat in two consecutive
/// measurements before it is published — single snapshots can be garbage
/// mid-animation, mid-⌘-drag, or during display transitions.
///
/// Occlusion state is deliberately unused: on macOS 26 it reports "occluded"
/// even for plainly visible status items (verified empirically).
///
/// Main-thread only, like the rest of the app: timers and observers are
/// scheduled on the main run loop.
extension Notification.Name {
    /// Posted after every newly confirmed layout classification, alongside
    /// the single-consumer `onConfirmedChange` closure.
    static let pelmetLayoutDidChange = Notification.Name("PelmetLayoutDidChange")
}

final class NotchLayoutMonitor {

    static let shared = NotchLayoutMonitor()

    // MARK: - Published state

    private(set) var confirmed: LayoutClassification?
    var onConfirmedChange: ((LayoutClassification) -> Void)?

    /// Geometry of the most recent measurement (fresh or not) — a fallback
    /// for consumers that need to position UI when a live read fails.
    private(set) var lastGeometry: MenuBarGeometry?

    // MARK: - Wiring

    private weak var separatorItem: NSStatusItem?
    private weak var toggleItem: NSStatusItem?
    private var isCollapsed: () -> Bool = { false }

    private var pendingMeasurement: Timer?
    private struct ItemMeasurement: Equatable {
        let frame: CGRect
        let visibility: ItemVisibility
    }

    private struct MeasurementDigest: Equatable {
        let items: [ItemMeasurement]
        let separatorHealth: SeparatorHealth
        let toggleVisible: Bool

        init(classification: LayoutClassification) {
            items = classification.items.map {
                ItemMeasurement(frame: $0.frame, visibility: $0.visibility)
            }
            separatorHealth = classification.separatorHealth
            toggleVisible = classification.toggleVisible
        }
    }
    private var candidate: MeasurementDigest?
    private var confirmedMeasurement: MeasurementDigest?
    private var deferredRetries = 0
    private var hasPendingSoftwareIslandConfiguration = false
    private var observers: [NSObjectProtocol] = []

    enum MeasurementReason: Equatable {
        case launch, expandSettled, collapseSettled, screenChanged, workspaceChanged
        case menuOpened, itemRecreated, softwareIslandConfigurationChanged

        var settleDelay: TimeInterval {
            switch self {
            case .launch: return 1.5
            case .expandSettled, .collapseSettled: return 0.35
            case .screenChanged: return 1.0
            case .workspaceChanged: return 1.0
            case .menuOpened: return 0
            case .softwareIslandConfigurationChanged: return 0.03
            case .itemRecreated: return 0.5
            }
        }
    }

    func attach(separator: NSStatusItem, toggle: NSStatusItem, isCollapsed: @escaping () -> Bool) {
        separatorItem = separator
        toggleItem = toggle
        self.isCollapsed = isCollapsed

        guard observers.isEmpty else { return }
        let observe: (NotificationCenter, Notification.Name, MeasurementReason) -> NSObjectProtocol = { center, name, reason in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.requestMeasurement(reason: reason)
            }
        }
        observers = [
            observe(.default, NSApplication.didChangeScreenParametersNotification, .screenChanged),
            observe(
                .default,
                .pelmetSoftwareIslandConfigurationDidChange,
                .softwareIslandConfigurationChanged
            ),
            observe(NSWorkspace.shared.notificationCenter, NSWorkspace.activeSpaceDidChangeNotification, .workspaceChanged),
            observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification, .workspaceChanged),
            observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didLaunchApplicationNotification, .workspaceChanged),
            observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didTerminateApplicationNotification, .workspaceChanged),
            observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didHideApplicationNotification, .workspaceChanged),
            observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didUnhideApplicationNotification, .workspaceChanged),
        ]
    }

    /// Call after a status item is removed and recreated (divider reset):
    /// the old weak reference dies with the old item.
    func reattach(separator: NSStatusItem, toggle: NSStatusItem) {
        separatorItem = separator
        toggleItem = toggle
        requestMeasurement(reason: .itemRecreated)
    }

    // MARK: - Measurement

    func requestMeasurement(reason: MeasurementReason) {
        if case .softwareIslandConfigurationChanged = reason {
            // Slider and toggle changes are deterministic user input. They do
            // not need the two-snapshot guard used for Window Server churn.
            hasPendingSoftwareIslandConfiguration = true
        }
        // Coalesce: the soonest requested measurement wins.
        let delay = reason.settleDelay
        if let pending = pendingMeasurement, pending.isValid,
           pending.fireDate.timeIntervalSinceNow < delay { return }
        pendingMeasurement?.invalidate()
        deferredRetries = 0
        let timer = Timer(timeInterval: max(delay, 0.01), repeats: false) { [weak self] _ in
            self?.measureNow()
        }
        pendingMeasurement = timer
        RunLoop.main.add(
            timer,
            forMode: reason == .softwareIslandConfigurationChanged ? .common : .default
        )
    }

    private func measureNow() {
        pendingMeasurement = nil
        let confirmsImmediately = hasPendingSoftwareIslandConfiguration
        hasPendingSoftwareIslandConfiguration = false

        // Mid-drag (⌘-drag of a status item) layouts are transient garbage.
        // A Settings slider drag is safe and must update while the mouse is down.
        if !confirmsImmediately, NSEvent.pressedMouseButtons != 0, deferredRetries < 6 {
            deferredRetries += 1
            pendingMeasurement = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                self?.measureNow()
            }
            return
        }

        guard let geometry = currentGeometry() else { return }
        lastGeometry = geometry
        let rawWindows = WindowListSource.statusItemWindows()
        guard !rawWindows.isEmpty else { return } // degraded read; keep prior state

        let classification = MenuBarLayoutClassifier.classify(
            rawItems: rawWindows,
            ownSeparatorFrame: separatorItem?.button?.window?.frame,
            ownToggleFrame: toggleItem?.button?.window?.frame,
            isCollapsed: isCollapsed(),
            geometry: geometry
        )

        publish(classification, confirmsImmediately: confirmsImmediately)
    }

    private func publish(
        _ classification: LayoutClassification,
        confirmsImmediately: Bool = false
    ) {
        let digest = MeasurementDigest(classification: classification)
        if digest == confirmedMeasurement {
            candidate = nil
            return
        }
        if confirmsImmediately || digest == candidate {
            candidate = nil
            confirmedMeasurement = digest
            confirmed = classification
            if let flag = ProcessInfo.processInfo.environment["PELMET_DEBUG_LAYOUT"] {
                print("Pelmet layout: swallowed=\(classification.swallowedCount) offscreenLeft=\(classification.offscreenLeftCount) separator=\(classification.separatorHealth) toggleVisible=\(classification.toggleVisible)")
                if flag == "verbose" {
                    let sep = separatorItem?.button?.window?.frame ?? .zero
                    let tog = toggleItem?.button?.window?.frame ?? .zero
                    print("  own separator=[\(Int(sep.minX)),\(Int(sep.maxX))] toggle=[\(Int(tog.minX)),\(Int(tog.maxX))]")
                    for item in classification.items where item.visibility != .visible {
                        print("  \(item.visibility): x=[\(Int(item.frame.minX)),\(Int(item.frame.maxX))] w=\(Int(item.frame.width))")
                    }
                }
                fflush(stdout)
            }
            // Multicast first: the activation engine rebuilds its directory
            // on this, and MenuBarManager's closure below reads that
            // directory — this order keeps them coherent within one snapshot.
            NotificationCenter.default.post(name: .pelmetLayoutDidChange, object: self)
            onConfirmedChange?(classification)
        } else {
            // New reading — require one confirming measurement before the UI moves.
            candidate = digest
            pendingMeasurement?.invalidate()
            pendingMeasurement = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                self?.measureNow()
            }
        }
    }

    func currentGeometry() -> MenuBarGeometry? {
        let softwareIslands = SoftwareIslandMonitor.shared
        softwareIslands.refresh()

        // Prefer a display with an enabled software island, then preserve the
        // existing physical-notch behavior. The toggle screen remains the
        // fallback for ordinary displays and collapse bookkeeping.
        let toggleScreenFrame = toggleItem?.button?.window?.screen?.frame
        let softwareIslandScreen = softwareIslands
            .preferredScreenFrame(preferred: toggleScreenFrame)
            .flatMap { frame in
            NSScreen.screens.first { $0.frame == frame }
        }
        let screen = softwareIslandScreen
            ?? NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
            ?? toggleItem?.button?.window?.screen
            ?? NSScreen.main
        guard let screen else { return nil }

        var notchRect: CGRect?
        if screen.safeAreaInsets.top > 0,
           let topLeft = screen.auxiliaryTopLeftArea,
           let topRight = screen.auxiliaryTopRightArea {
            notchRect = CGRect(
                x: topLeft.maxX,
                y: screen.frame.maxY - screen.safeAreaInsets.top,
                width: topRight.minX - topLeft.maxX,
                height: screen.safeAreaInsets.top
            )
        }

        let menuBarHeight = toggleItem?.button?.window?.frame.height
            ?? max(NSStatusBar.system.thickness, screen.safeAreaInsets.top)
        let softwareOverlayRect = softwareIslands.obstruction(
            on: screen,
            menuBarHeight: menuBarHeight
        )

        return MenuBarGeometry(
            screenFrame: screen.frame,
            notchRect: notchRect,
            menuBarHeight: menuBarHeight,
            softwareOverlayRect: softwareOverlayRect
        )
    }
}
