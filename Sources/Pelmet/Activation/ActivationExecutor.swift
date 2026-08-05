import AppKit
import ApplicationServices
import PelmetCore
import os

/// Opens status items only through actions explicitly advertised by macOS
/// Accessibility. This executor never creates mouse events, moves the pointer,
/// or rearranges menu bar items.
final class ActivationExecutor {

    static let shared = ActivationExecutor()

    private let detector = MenuOpenDetector()
    private let logger = Logger(
        subsystem: "com.ismatbabirli.Pelmet",
        category: "Activation"
    )

    private(set) var isActivating = false
    private var lastActivation = Date.distantPast
    private var abortObservers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var aborted = false
    private var activeCompletion: ((ActivationResult) -> Void)?
    private var sessionBaseline: Set<Int> = []
    private var verificationPoint = CGPoint.zero

    /// A successful Accessibility action may leave a menu in the user's hands.
    /// Keep auto-rehide paused until that menu closes, without touching input.
    private var quiescing = false
    private var quiescenceGeneration = 0

    private static let minActivationInterval: TimeInterval = 1.0
    private static let verificationDeadline: TimeInterval = 1.2

    /// AX calls can block while another process is unresponsive. Keep every
    /// cross-process action off the main thread and bound it with a timeout.
    private let ioQueue = DispatchQueue(
        label: "com.ismatbabirli.Pelmet.activation-io",
        qos: .userInitiated
    )

    var isDisabledByEnv: Bool {
        ProcessInfo.processInfo.environment["PELMET_DISABLE_ACTIVATION"] == "1"
    }

    /// Resolve `recordID` and ask its live AX element to show its associated
    /// menu or perform its primary action. No synthetic fallback is allowed.
    func activate(
        recordID: String,
        engine: StatusItemActivationEngine,
        completion: @escaping (ActivationResult) -> Void
    ) {
        guard !isDisabledByEnv else {
            return completion(.failed(.permissionDenied))
        }
        guard engine.canActivate else {
            return completion(.failed(.permissionDenied))
        }
        guard !isActivating else {
            return completion(.failed(.busy))
        }
        if quiescing {
            cancelQuiescence()
        }
        guard Date().timeIntervalSince(lastActivation) >= Self.minActivationInterval else {
            return completion(.failed(.busy))
        }
        guard NSEvent.pressedMouseButtons == 0 else {
            return completion(.failed(.userInteracting))
        }
        guard let target = engine.directory.records.first(where: { $0.id == recordID }) else {
            return completion(.failed(.itemVanished))
        }

        // Pelmet itself pushed this item off the left edge. Revealing the bar
        // is pointer-free; the user can retry once the directory refreshes.
        if target.visibility == .offscreenLeft {
            MenuBarManager.shared.expandForActivation()
            return completion(.failed(.itemVanished))
        }
        guard target.visibility != .suspectedGhost,
              let element = engine.elementForRecordID[recordID]
        else {
            return completion(.failed(.actionUnsupported))
        }

        isActivating = true
        aborted = false
        lastActivation = Date()
        activeCompletion = completion
        verificationPoint = CGPoint(x: target.frame.midX, y: target.frame.midY)
        sessionBaseline = detector.baselineWindowIDs()
        installAbortObservers()

        performAccessibilityAction(on: element)
    }

    private func performAccessibilityAction(on element: AXUIElement) {
        ioQueue.async { [weak self] in
            guard let self else { return }
            AXUIElementSetMessagingTimeout(element, 1.0)

            var copiedNames: CFArray?
            let copyError = AXUIElementCopyActionNames(element, &copiedNames)
            let names = copyError == .success ? copiedNames as? [String] : nil
            guard let names,
                  let action = AccessibilityActionSelector.preferred(from: names)
            else {
                DispatchQueue.main.async { [weak self] in
                    self?.logger.info("Status item exposes no pointer-safe Accessibility action")
                    self?.finish(.failed(.actionUnsupported))
                }
                return
            }

            let error = AXUIElementPerformAction(element, action.rawValue as CFString)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.aborted {
                    self.finish(.failed(.interrupted))
                } else if error == .success {
                    self.startVerification(allowUnverifiedSuccess: true)
                } else if error == .cannotComplete {
                    // Apple notes that cannotComplete can be returned even
                    // when an app eventually handles an AX action. Verify it,
                    // but do not claim soft success without evidence.
                    self.startVerification(allowUnverifiedSuccess: false)
                } else {
                    self.logger.info(
                        "Pointer-safe Accessibility action failed: \(error.rawValue)"
                    )
                    self.finish(.failed(.actionUnsupported))
                }
            }
        }
    }

    private func startVerification(allowUnverifiedSuccess: Bool) {
        let baseline = sessionBaseline
        let point = verificationPoint
        let start = Date()

        func poll() {
            guard self.isActivating else { return }
            if self.aborted {
                return self.finish(.failed(.interrupted))
            }
            if self.detector.newMenuWindowID(near: point, baseline: baseline) != nil {
                return self.finish(.activated(.menuOpened))
            }
            if Date().timeIntervalSince(start) >= Self.verificationDeadline {
                return self.finish(
                    allowUnverifiedSuccess
                        ? .activated(.unverified)
                        : .failed(.timedOut)
                )
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { poll() }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { poll() }
    }

    private func finish(_ result: ActivationResult) {
        guard isActivating else { return }
        isActivating = false
        removeAbortObservers()
        StatusItemActivationEngine.debugTrace { "activation finished: \(result)" }

        let completion = activeCompletion
        activeCompletion = nil

        if case .activated = result {
            // Hold auto-rehide open before the Shelf closes. This hold only
            // observes menu state and user input; it never posts input.
            UIActivityTracker.shared.surfaceOpened()
            beginQuiescence(baseline: sessionBaseline)
        }
        completion?(result)
    }

    // MARK: - Post-activation observation

    private func beginQuiescence(baseline: Set<Int>) {
        quiescing = true
        quiescenceGeneration += 1
        let generation = quiescenceGeneration
        let start = Date()
        var closedStreak = 0

        func poll() {
            guard generation == self.quiescenceGeneration else { return }
            let menusOpen = self.detector.hasNewMenuWindows(baseline: baseline)
            closedStreak = menusOpen ? 0 : closedStreak + 1
            let decision = QuiescencePolicy.decide(
                menusOpen: menusOpen,
                closedStreak: closedStreak,
                buttonsDown: NSEvent.pressedMouseButtons != 0,
                secondsSinceLastInput: Self.secondsSinceLastUserInput(),
                elapsed: Date().timeIntervalSince(start)
            )
            switch decision {
            case .wait:
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { poll() }
            case .proceed, .giveUp:
                self.endQuiescence(generation: generation)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { poll() }
    }

    private func cancelQuiescence() {
        quiescenceGeneration += 1
        quiescing = false
        UIActivityTracker.shared.surfaceClosed()
    }

    private func endQuiescence(generation: Int) {
        guard generation == quiescenceGeneration else { return }
        quiescing = false
        UIActivityTracker.shared.surfaceClosed()
    }

    /// Read-only session input age used to avoid re-hiding while a menu click
    /// is still settling. No events are created or posted here.
    private static func secondsSinceLastUserInput() -> TimeInterval {
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .rightMouseDown]
        return types
            .map {
                CGEventSource.secondsSinceLastEventType(
                    .combinedSessionState,
                    eventType: $0
                )
            }
            .min() ?? .greatestFiniteMagnitude
    }

    // MARK: - Abort rails

    private func installAbortObservers() {
        guard abortObservers.isEmpty else { return }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let markAborted: (Notification) -> Void = { [weak self] _ in
            self?.aborted = true
        }
        abortObservers = [
            (workspaceCenter, workspaceCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main,
                using: markAborted
            )),
            (workspaceCenter, workspaceCenter.addObserver(
                forName: NSWorkspace.sessionDidResignActiveNotification,
                object: nil,
                queue: .main,
                using: markAborted
            )),
            (DistributedNotificationCenter.default() as NotificationCenter,
             DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("com.apple.screenIsLocked"),
                object: nil,
                queue: .main,
                using: markAborted
             )),
        ]
    }

    private func removeAbortObservers() {
        abortObservers.forEach { $0.center.removeObserver($0.token) }
        abortObservers = []
    }
}
