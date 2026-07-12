import AppKit
import ApplicationServices
import PelmetCore
import os

/// Drives a pure `ActivationSession` against real effects: synthetic
/// clicks, AXPress, drag-to-expose, verification, and the safety rails that
/// keep Pelmet from fighting the user or wedging the mouse.
///
/// One activation at a time. Everything decision-shaped lives in the
/// session; this only performs effects and reports results back.
final class ActivationExecutor {

    static let shared = ActivationExecutor()

    private let poster: EventPosting
    private let detector = MenuOpenDetector()
    private let logger = Logger(subsystem: "com.ismatbabirli.Pelmet", category: "Activation")

    /// True while an activation is in flight. The Shelf reads this to keep
    /// its dismiss monitors from closing the panel when our own synthetic
    /// click lands in another app (global monitors see cross-app events).
    private(set) var isActivating = false
    private var lastActivation = Date.distantPast
    private var lastDrag = Date.distantPast
    private var abortObservers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var aborted = false

    /// State for the single in-flight activation. The session is a value
    /// type but the effect loop is async, so it lives here rather than
    /// threading an `inout` through escaping callbacks.
    private var session: ActivationSession?
    private var activeTarget: MenuBarItemRecord?
    private var activeEngine: StatusItemActivationEngine?
    private var activeCompletion: ((ActivationResult) -> Void)?
    private var activeGeometry: MenuBarGeometry?
    /// Frontmost app before appMenuClearance activated Finder — restored
    /// when the session finishes so activation never steals focus for good.
    private var previousFrontmost: NSRunningApplication?
    /// Right-of-notch item frames captured just before the expose drag —
    /// diffing against the post-drag list finds where an identity-less
    /// target landed (clicking its stale frame could hit the wrong icon).
    private var preDragRightOfNotchFrames: [CGRect]?

    private static let minActivationInterval: TimeInterval = 1.0
    private static let minDragInterval: TimeInterval = 5.0

    init(poster: EventPosting = SyntheticEventPoster()) {
        self.poster = poster
    }

    var isDisabledByEnv: Bool {
        ProcessInfo.processInfo.environment["PELMET_DISABLE_ACTIVATION"] == "1"
    }

    /// Resolve `recordID` in the engine's current directory and run the
    /// activation. `completion` is always called on main.
    func activate(
        recordID: String,
        engine: StatusItemActivationEngine,
        completion: @escaping (ActivationResult) -> Void
    ) {
        guard !isDisabledByEnv else { return completion(.failed(.permissionDenied)) }
        guard engine.canActivate else { return completion(.failed(.permissionDenied)) }
        guard !isActivating else { return completion(.failed(.busy)) }
        guard Date().timeIntervalSince(lastActivation) >= Self.minActivationInterval else {
            return completion(.failed(.busy))
        }
        guard NSEvent.pressedMouseButtons == 0 else {
            return completion(.failed(.userInteracting))
        }
        guard let geometry = NotchLayoutMonitor.shared.currentGeometry()
            ?? NotchLayoutMonitor.shared.lastGeometry else {
            return completion(.failed(.itemVanished))
        }
        guard let target = engine.directory.records.first(where: { $0.id == recordID }) else {
            return completion(.failed(.itemVanished))
        }

        // Offscreen-left targets are Pelmet's own collapse hiding them:
        // expand and let the next directory refresh make them clickable,
        // rather than clicking into the void now.
        if target.visibility == .offscreenLeft {
            MenuBarManager.shared.expandForActivation()
            return completion(.failed(.itemVanished))
        }

        let strategies = ActivationPlanner.plan(
            target: target,
            allItems: engine.directory.records,
            ownFrames: MenuBarManager.shared.ownItemFrames,
            geometry: geometry,
            hasAXElement: engine.elementForRecordID[recordID] != nil
        )

        isActivating = true
        aborted = false
        lastActivation = Date()
        lastOpenedMenuID = nil
        activeGeometry = geometry
        previousFrontmost = nil
        preDragRightOfNotchFrames = nil
        installAbortObservers()

        session = ActivationSession(
            strategies: strategies,
            targetWasSwallowed: target.visibility == .swallowedByNotch
        )
        activeTarget = target
        activeEngine = engine
        activeCompletion = completion
        dispatch(session!.handle(.begin))
    }

    // MARK: - Effect interpretation

    /// Feed an event through the session and dispatch the resulting effects.
    private func advance(_ event: ActivationSession.Event) {
        guard session != nil else { return }
        let effects = session!.handle(event)
        dispatch(effects)
    }

    private func dispatch(_ effects: [ActivationSession.Effect]) {
        guard let target = activeTarget, let engine = activeEngine else { return }
        for effect in effects {
            switch effect {
            case .perform(let strategy):
                perform(strategy, target: target, engine: engine) { [weak self] event in
                    self?.advance(event)
                }
                return // async; the callback re-enters via advance()

            case .startVerification(let deadline):
                startVerification(near: pendingVerificationPoint, deadline: deadline) { [weak self] event in
                    self?.advance(event)
                }
                return

            case .releaseMouseButtons:
                poster.releaseMouseButtons()

            case .restoreDrag(let plan):
                scheduleRestore(plan)

            case .finish(let result):
                finish(result)
                return
            }
        }
    }

    /// Synthetic events, AX position reads and AXPress all block their
    /// caller for tens of ms to seconds (a hung target). They must never run
    /// on the main thread — the whole AX architecture is built around that.
    /// Main-thread guards run first; the blocking work hops to `ioQueue`;
    /// the result reports back on main.
    private let ioQueue = DispatchQueue(label: "com.ismatbabirli.Pelmet.activation-io", qos: .userInitiated)

    private func perform(
        _ strategy: ActivationStrategy,
        target: MenuBarItemRecord,
        engine: StatusItemActivationEngine,
        report: @escaping (ActivationSession.Event) -> Void
    ) {
        if aborted { return report(.aborted(.interrupted)) }
        if NSEvent.pressedMouseButtons != 0 { return report(.aborted(.userInteracting)) }

        switch strategy {
        case .expandCollapsedBar:
            MenuBarManager.shared.expandForActivation()
            report(.stepCompleted)

        case .syntheticClick(let point):
            offMainClick(at: point, report: report)

        case .clickTargetAfterReflow:
            // Re-resolve the target's live position after the reflow — off
            // main, since it may read the AX element's position. No stale
            // fallback here: clicking the pre-reflow frame after items
            // shifted would hit a DIFFERENT icon.
            let element = engine.elementForRecordID[target.id]
            let pid = target.identity?.pid
            let preDrag = preDragRightOfNotchFrames
            let notch = activeGeometry?.notchRect
            ioQueue.async { [weak self] in
                guard let self else { return }
                let point = self.reresolvedPoint(
                    element: element, pid: pid, preDragFrames: preDrag, notch: notch
                )
                let ok = point.map { self.poster.click(atAppKit: $0) } ?? false
                DispatchQueue.main.async {
                    if let point { self.pendingVerificationPoint = point }
                    report(ok ? .stepCompleted : .stepFailed)
                }
            }

        case .axPress:
            guard let element = engine.elementForRecordID[target.id] else {
                return report(.stepFailed)
            }
            ioQueue.async {
                // Bound the round-trip on THIS element (the messaging timeout
                // is per-ref, so the reader's app-ref timeout doesn't cover
                // this child) so a hung target fails fast, not forever.
                AXUIElementSetMessagingTimeout(element, 1.0)
                let ok = AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
                DispatchQueue.main.async { report(ok ? .stepCompleted : .stepFailed) }
            }

        case .appMenuClearance:
            // Remember who had focus — clearance must be a loan, not a theft.
            let frontmost = NSWorkspace.shared.frontmostApplication
            if frontmost?.bundleIdentifier != "com.apple.finder" {
                previousFrontmost = frontmost
            }
            NSRunningApplication
                .runningApplications(withBundleIdentifier: "com.apple.finder")
                .first?.activate(options: [])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { report(.stepCompleted) }

        case .dragToExpose(let plan):
            guard Date().timeIntervalSince(lastDrag) >= Self.minDragInterval else {
                return report(.stepFailed)
            }
            lastDrag = Date()
            preDragRightOfNotchFrames = rightOfNotchFrames()
            ioQueue.async { [weak self] in
                let ok = self?.poster.commandDrag(fromAppKit: plan.from, toAppKit: plan.to) ?? false
                DispatchQueue.main.async { report(ok ? .stepCompleted : .stepFailed) }
            }
        }
    }

    /// Item frames currently right of the notch (main thread).
    private func rightOfNotchFrames() -> [CGRect] {
        guard let notch = activeGeometry?.notchRect else { return [] }
        return WindowListSource.statusItemWindows()
            .map(\.frame)
            .filter { $0.minX > notch.maxX }
    }

    private func offMainClick(at point: CGPoint, report: @escaping (ActivationSession.Event) -> Void) {
        pendingVerificationPoint = point
        ioQueue.async { [weak self] in
            let ok = self?.poster.click(atAppKit: point) ?? false
            DispatchQueue.main.async { report(ok ? .stepCompleted : .stepFailed) }
        }
    }

    private var pendingVerificationPoint: CGPoint = .zero

    private func startVerification(
        near point: CGPoint,
        deadline: TimeInterval,
        report: @escaping (ActivationSession.Event) -> Void
    ) {
        let baseline = detector.baselineWindowIDs()
        let start = Date()
        func poll() {
            if aborted { return report(.aborted(.interrupted)) }
            if let id = detector.newMenuWindowID(near: point, baseline: baseline) {
                lastOpenedMenuID = id
                return report(.verified(.menuOpened))
            }
            if Date().timeIntervalSince(start) >= deadline {
                return report(.verificationTimedOut)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { poll() }
        }
        // Give the click a beat to open the menu before the first poll.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { poll() }
    }

    private var lastOpenedMenuID: Int?

    /// The reflow moved the target; find where it landed. Runs on `ioQueue`.
    ///
    /// The AX element's live `kAXPosition` is the reliable source: on Tahoe
    /// every status window is owned by Control Center, so matching a
    /// CGWindow by the app's PID finds nothing there. For identity-less
    /// targets, diff the right-of-notch frames against the pre-drag capture
    /// — the newly appeared frame is where the target reflowed to. Nil when
    /// nothing is trustworthy: clicking a stale frame after items shifted
    /// would open a DIFFERENT app's menu.
    private func reresolvedPoint(
        element: AXUIElement?,
        pid: Int32?,
        preDragFrames: [CGRect]?,
        notch: CGRect?
    ) -> CGPoint? {
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        if let element,
           let frame = LiveAXMenuBarExtrasReader.frame(of: element, primaryMaxY: primaryMaxY, timeout: 1.0) {
            return CGPoint(x: frame.midX, y: frame.midY)
        }
        if let pid, let match = WindowListSource.statusItemWindows().first(where: { $0.ownerPID == pid }) {
            return CGPoint(x: match.frame.midX, y: match.frame.midY)
        }
        if let preDragFrames, let notch {
            let fresh = WindowListSource.statusItemWindows()
                .map(\.frame)
                .filter { $0.minX > notch.maxX }
            let appeared = fresh.filter { frame in
                !preDragFrames.contains { abs($0.minX - frame.minX) < 3 && abs($0.width - frame.width) < 3 }
            }
            // The exposed slot opens right beside the notch; take the new
            // frame nearest to it. Ambiguity (several new frames) still
            // resolves to the notch-adjacent one — that's where reflow
            // inserts the freed item.
            if let landed = appeared.min(by: { $0.minX < $1.minX }) {
                return CGPoint(x: landed.midX, y: landed.midY)
            }
        }
        return nil
    }

    private func scheduleRestore(_ plan: DragPlan) {
        // Restore only after the opened menu closes, so we don't yank the
        // bar out from under an open menu. Bounded wait.
        let menuID = lastOpenedMenuID
        let deadline = Date().addingTimeInterval(30)
        func waitAndRestore() {
            let menuClosed = menuID.map { !detector.isWindowPresent($0) } ?? true
            if menuClosed || Date() > deadline {
                guard NSEvent.pressedMouseButtons == 0 else {
                    // User is interacting; don't fight them. Leave the order
                    // as-is rather than risk a tug of war.
                    return
                }
                let restorePoint = CGPoint(x: plan.neighborFrame.midX, y: plan.neighborFrame.midY)
                poster.commandDrag(fromAppKit: plan.to, toAppKit: restorePoint)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { waitAndRestore() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { waitAndRestore() }
    }

    private func finish(_ result: ActivationResult) {
        isActivating = false
        removeAbortObservers()
        StatusItemActivationEngine.debugTrace { "activation finished: \(result)" }
        // Clearance borrowed focus for Finder; give it back.
        if let previousFrontmost, !previousFrontmost.isTerminated {
            previousFrontmost.activate(options: [])
        }
        previousFrontmost = nil
        let completion = activeCompletion
        session = nil
        activeTarget = nil
        activeEngine = nil
        activeCompletion = nil
        completion?(result)
    }

    // MARK: - Abort rails

    private func installAbortObservers() {
        guard abortObservers.isEmpty else { return }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let markAborted: (Notification) -> Void = { [weak self] _ in self?.aborted = true }
        abortObservers = [
            (workspaceCenter, workspaceCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main, using: markAborted
            )),
            (workspaceCenter, workspaceCenter.addObserver(
                forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main, using: markAborted
            )),
            (DistributedNotificationCenter.default() as NotificationCenter,
             DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main, using: markAborted
            )),
        ]
    }

    private func removeAbortObservers() {
        abortObservers.forEach { $0.center.removeObserver($0.token) }
        abortObservers = []
    }
}
