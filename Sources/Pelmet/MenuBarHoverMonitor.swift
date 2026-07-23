import AppKit
import os
import PelmetCore

/// Observes permission-free pointer movement and emits edge transitions for
/// the full menu bar band on the display currently hosting Pelmet's toggle.
final class MenuBarHoverMonitor: NSObject {

    typealias Region = (toggleFrame: CGRect, screenFrame: CGRect)

    private let logger = Logger(
        subsystem: "com.ismatbabirli.Pelmet",
        category: "MenuBarHoverMonitor"
    )

    private var tracker = MenuBarHoverTracker()
    private var regionProvider: (() -> Region?)?
    private var onTransition: ((MenuBarHoverTransition) -> Void)?

    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private weak var toggleButton: NSStatusBarButton?
    private var toggleTrackingArea: NSTrackingArea?
    private var running = false

    var isPointerInMenuBar: Bool {
        running && tracker.isPointerInside
    }

    func attach(to button: NSStatusBarButton) {
        if toggleButton === button { return }
        removeToggleTrackingArea()
        toggleButton = button
        if running {
            installToggleTrackingArea()
            evaluatePointer()
        }
    }

    func start(
        regionProvider: @escaping () -> Region?,
        onTransition: @escaping (MenuBarHoverTransition) -> Void
    ) {
        self.regionProvider = regionProvider
        self.onTransition = onTransition

        guard !running else {
            evaluatePointer()
            return
        }
        running = true

        let mask: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseUp,
            .rightMouseUp,
            .otherMouseUp,
        ]
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.evaluatePointer()
        }
        if globalEventMonitor == nil {
            logger.error("Unable to install the global hover event monitor")
        }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.evaluatePointer()
            return event
        }

        installToggleTrackingArea()
        installDisplayObservers()
        evaluatePointer()
    }

    func stop() {
        guard running else { return }
        running = false

        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
        }
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
        }
        globalEventMonitor = nil
        localEventMonitor = nil

        removeToggleTrackingArea()
        observers.forEach { $0.center.removeObserver($0.token) }
        observers = []
        tracker.reset()
        regionProvider = nil
        onTransition = nil
    }

    @objc private func mouseEntered(_ event: NSEvent) {
        evaluatePointer()
    }

    @objc private func mouseExited(_ event: NSEvent) {
        evaluatePointer()
    }

    private func evaluatePointer() {
        guard running else { return }
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.evaluatePointer()
            }
            return
        }

        let region = regionProvider?()
        let transition = tracker.update(
            enabled: true,
            buttonsDown: NSEvent.pressedMouseButtons != 0,
            point: NSEvent.mouseLocation,
            toggleFrame: region?.toggleFrame,
            screenFrame: region?.screenFrame
        )
        if let transition {
            onTransition?(transition)
        }
    }

    private func installToggleTrackingArea() {
        guard toggleTrackingArea == nil, let toggleButton else { return }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        toggleButton.addTrackingArea(area)
        toggleTrackingArea = area
    }

    private func removeToggleTrackingArea() {
        if let toggleTrackingArea, let toggleButton {
            toggleButton.removeTrackingArea(toggleTrackingArea)
        }
        toggleTrackingArea = nil
    }

    private func installDisplayObservers() {
        guard observers.isEmpty else { return }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers = [
            (.default, NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.evaluatePointer()
            }),
            (workspaceCenter, workspaceCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.evaluatePointer()
            }),
            (workspaceCenter, workspaceCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.evaluatePointer()
            }),
        ]
    }
}
