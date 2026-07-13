import AppKit
import SwiftUI
import PelmetCore

/// Owns the Shelf panel's lifecycle: placement below the notch, dismiss
/// triggers, live content updates, and the auto-rehide pause while open.
/// Every show() is user-initiated (click, hotkey, menu item) — the Shelf
/// NEVER auto-shows, which is also what keeps it out of fullscreen apps
/// uninvited. (A future hover accelerator must preserve that constraint.)
final class ShelfPanelController {

    static let shared = ShelfPanelController()

    enum ShowReason {
        case toggleClick, hotkey, menu
    }

    private(set) lazy var panel: ShelfPanel = makePanel()
    private lazy var viewModel = ShelfViewModel(engine: MenuBarManager.shared.shelfEngine)
    private var hosting: NSHostingController<ShelfView>?

    private weak var anchorButton: NSStatusBarButton?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var emptyAutoHideTimer: Timer?
    private var lastRowCount = 0

    var isVisible: Bool { panelIfLoaded?.isVisible ?? false }
    private var panelLoaded = false
    private var panelIfLoaded: ShelfPanel? { panelLoaded ? panel : nil }

    // MARK: - Show / hide

    func show(anchor: NSStatusBarButton?, reason: ShowReason) {
        anchorButton = anchor
        let panel = self.panel // force lazy construction (sets `hosting`)

        // Fresh facts for a surface the user is looking at right now.
        NotchLayoutMonitor.shared.requestMeasurement(reason: .menuOpened)
        viewModel.update(entries: LayoutStatus.shared.shelfEntries)
        lastRowCount = viewModel.rows.count

        guard let hosting else { return }
        hosting.view.layoutSubtreeIfNeeded()
        let size = hosting.view.fittingSize
        let geometry = NotchLayoutMonitor.shared.currentGeometry()
            ?? NotchLayoutMonitor.shared.lastGeometry
            ?? fallbackGeometry()
        let frame = ShelfPlacement.panelFrame(
            panelSize: size,
            anchorFrame: anchor?.window?.frame,
            geometry: geometry
        )

        let wasVisible = panel.isVisible
        panel.setFrame(frame, display: true)

        if !wasVisible {
            UIActivityTracker.shared.surfaceOpened()
            installDismissMonitors()
            revealPanel(reason: reason)
        } else if reason == .hotkey {
            panel.makeKey()
        }
    }

    func hide(animated: Bool = true) {
        guard isVisible else { return }
        removeDismissMonitors()
        emptyAutoHideTimer?.invalidate()
        emptyAutoHideTimer = nil
        viewModel.expandedExplanationID = nil

        let finish = { [panel] in
            panel.orderOut(nil)
            panel.alphaValue = 1
        }
        if animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.12
                panel.animator().alphaValue = 0
            }, completionHandler: finish)
        } else {
            finish()
        }
        UIActivityTracker.shared.surfaceClosed()
    }

    /// Live refresh from every confirmed layout snapshot while open.
    func update(entries: [ShelfEntryModel]) {
        guard isVisible else { return }
        viewModel.update(entries: entries)

        if entries.isEmpty, lastRowCount > 0 {
            // Everything fits again — say so briefly, then get out of the way.
            emptyAutoHideTimer?.invalidate()
            emptyAutoHideTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
                self?.hide()
            }
        } else if !entries.isEmpty {
            emptyAutoHideTimer?.invalidate()
            emptyAutoHideTimer = nil
        }
        lastRowCount = entries.count

        if let hosting {
            hosting.view.layoutSubtreeIfNeeded()
            let size = hosting.view.fittingSize
            if abs(size.height - panel.frame.height) > 0.5 {
                var frame = panel.frame
                frame.origin.y = frame.maxY - size.height
                frame.size = size
                panel.setFrame(frame, display: true)
            }
        }
    }

    // MARK: - Panel construction

    private func makePanel() -> ShelfPanel {
        let panel = ShelfPanel()
        let hosting = NSHostingController(rootView: ShelfView(model: viewModel))
        hosting.view.wantsLayer = true
        panel.contentViewController = hosting
        self.hosting = hosting
        viewModel.onRequestClose = { [weak self] in self?.hide() }
        panel.onKeyCommand = { [weak self] command in
            self?.viewModel.handle(command) ?? false
        }
        panelLoaded = true
        return panel
    }

    private func revealPanel(reason: ShowReason) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduceMotion {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        } else {
            // Fade in with a 4pt downward settle.
            let target = panel.frame
            var start = target
            start.origin.y += 4
            panel.setFrame(start, display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
                panel.animator().setFrame(target, display: true)
            }
        }
        // Always become key so Esc and arrow-key navigation work regardless
        // of how the Shelf was opened. A .nonactivatingPanel becomes key
        // without activating Pelmet, so this doesn't steal focus from the
        // frontmost app. `reason` no longer changes this — kept for the
        // future hover accelerator, which will want to stay non-key.
        _ = reason
        panel.makeKey()
    }

    private func fallbackGeometry() -> MenuBarGeometry {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
        let frame = screen?.frame ?? CGRect(x: 0, y: 0, width: 1512, height: 982)
        return MenuBarGeometry(
            screenFrame: frame,
            notchRect: nil,
            menuBarHeight: max(NSStatusBar.system.thickness, screen?.safeAreaInsets.top ?? 24)
        )
    }

    // MARK: - Dismiss triggers

    private func installDismissMonitors() {
        // Global mouse monitors are permission-free (only keyboard monitoring
        // is Accessibility-gated). Clicks on the toggle itself are left to
        // the click matrix — hiding here on mouseDown would make the
        // toggle's mouseUp handler reopen the shelf it just closed.
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self else { return }
            // Our own synthetic events (activation clicks, the post-session
            // restore drag) land in other apps and a global monitor sees
            // them. Never treat those as a dismiss — they carry the poster's
            // source tag, and mid-activation nothing dismisses at all.
            if ActivationExecutor.shared.isActivating { return }
            if Self.isPelmetSynthetic(event) { return }
            if let toggleWindow = self.anchorButton?.window,
               toggleWindow.frame.contains(NSEvent.mouseLocation) { return }
            self.hide()
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            if ActivationExecutor.shared.isActivating { return event }
            if Self.isPelmetSynthetic(event) { return event }
            if event.window !== self.panelIfLoaded {
                if let toggleWindow = self.anchorButton?.window, event.window === toggleWindow {
                    return event
                }
                self.hide()
            }
            return event
        }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers = [
            (workspaceCenter, workspaceCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                self?.hide(animated: false)
            }),
            (.default, NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                self?.hide(animated: false)
            }),
        ]
    }

    /// Events posted by `SyntheticEventPoster` carry its source tag.
    private static func isPelmetSynthetic(_ event: NSEvent) -> Bool {
        event.cgEvent?.getIntegerValueField(.eventSourceUserData)
            == SyntheticEventPoster.sourceUserData
    }

    private func removeDismissMonitors() {
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        globalMouseMonitor = nil
        localMouseMonitor = nil
        observers.forEach { $0.center.removeObserver($0.token) }
        observers = []
    }
}
