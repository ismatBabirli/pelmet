import AppKit
import ApplicationServices
import PelmetCore

/// The seam between the Shelf UI and the (opt-in, Accessibility-gated)
/// activation machinery. Main-thread public surface, closure callbacks —
/// house style.
///
/// The engine is ALWAYS present and publishes a directory even without any
/// permission: identity comes free from CGWindow owner PIDs on macOS ≤ 15
/// (Sequoia); on Tahoe, where Control Center re-parents every status-item
/// window, the ungranted directory honestly degrades to `.framesOnly`.
/// With the grant, an AX sweep (`kAXExtrasMenuBarAttribute` per running
/// app) restores identity on Tahoe and adds item titles everywhere.
protocol StatusItemActivating: AnyObject {
    var availability: ActivationAvailability { get }
    var onAvailabilityChange: ((ActivationAvailability) -> Void)? { get set }

    var directory: DirectorySnapshot { get }
    var onDirectoryChange: ((DirectorySnapshot) -> Void)? { get set }

    /// True when the directory carries (or could carry) real ownership.
    var canIdentify: Bool { get }
    /// True only when activation can actually run (permission granted).
    var canActivate: Bool { get }

    /// Descriptors the Shelf deriver uses to make rows one-click
    /// activatable — empty unless activation can actually run. Tokens are
    /// `MenuBarItemRecord` ids, fed back to `activate(recordID:)`.
    var activatableDescriptors: [EngineItemDescriptor] { get }

    func setEnabled(_ enabled: Bool)
    func requestAccess()
    /// Route any "enable one-click access" affordance to the right outcome:
    /// fire the system prompt, deep-link to System Settings when the OS won't
    /// re-show it, or just enable when already trusted. `proactive` = the
    /// passive first-run auto-prompt (keep the engine OFF until the grant
    /// lands); an explicit user tap passes `false` and enables immediately.
    func offerOneClick(proactive: Bool)
    func refreshDirectory(reason: String)
    func activate(recordID: String, completion: @escaping (ActivationResult) -> Void)
}

extension Notification.Name {
    /// Posted whenever the engine's availability changes — the multicast
    /// channel for SwiftUI surfaces (the closure is single-consumer).
    static let pelmetActivationAvailabilityChanged =
        Notification.Name("PelmetActivationAvailabilityChanged")
}

/// SwiftUI-observable mirror of the engine's availability, for Settings and
/// the Shelf.
final class ActivationStatus: ObservableObject {

    static let shared = ActivationStatus()

    @Published private(set) var availability: ActivationAvailability

    private var observer: NSObjectProtocol?

    private init() {
        availability = StatusItemActivationEngine.shared.availability
        observer = NotificationCenter.default.addObserver(
            forName: .pelmetActivationAvailabilityChanged,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.availability = StatusItemActivationEngine.shared.availability
        }
    }
}

final class StatusItemActivationEngine: StatusItemActivating {

    static let shared = StatusItemActivationEngine()

    // MARK: - Published state

    private(set) var availability: ActivationAvailability = .notDetermined {
        didSet {
            if availability != oldValue {
                onAvailabilityChange?(availability)
                NotificationCenter.default.post(name: .pelmetActivationAvailabilityChanged, object: self)
            }
        }
    }
    var onAvailabilityChange: ((ActivationAvailability) -> Void)?

    private(set) var directory: DirectorySnapshot = .empty
    var onDirectoryChange: ((DirectorySnapshot) -> Void)?

    var canIdentify: Bool { directory.fidelity == .identified }
    var canActivate: Bool { availability == .granted }

    var activatableDescriptors: [EngineItemDescriptor] {
        guard canActivate else { return [] }
        return directory.records
            .filter { $0.visibility == .swallowedByNotch }
            .map { record in
                EngineItemDescriptor(
                    token: record.id,
                    // nil when identity is unknown — the deriver numbers the
                    // fallback so rows never collapse into identical
                    // unnumbered "Hidden item" entries.
                    title: record.identity.map { $0.axTitle ?? $0.appName },
                    ownerPID: record.identity?.pid,
                    frame: record.frame
                )
            }
    }

    // MARK: - Internals

    /// Injectable AX seam — swapped out in future tests.
    var extrasReader: MenuBarExtrasReading = LiveAXMenuBarExtrasReader()

    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private let ownPID = Int32(ProcessInfo.processInfo.processIdentifier)

    /// All AX reads happen here, never on main — a hung app blocks only
    /// this queue (per-app 1s messaging timeout + sweep deadline).
    private let sweepQueue = DispatchQueue(
        label: "com.ismatbabirli.Pelmet.ax-sweep", qos: .userInitiated
    )
    private var isSweeping = false
    private var sweepGeneration = 0
    /// Bounded retries when a swallowed record publishes without identity —
    /// position reads racing a mid-toggle bar animation resolve on a
    /// re-read moments later. Reset on every confirmed layout change; capped
    /// so apps that genuinely expose no AX extras don't cause a rebuild loop.
    private var healAttempts = 0
    private var axCache: [pid_t: (observations: [AXExtraObservation], stamp: Date)] = [:]
    private var slowPIDs: Set<pid_t> = []
    /// Live AX elements for the current directory's records (AXPress path).
    private(set) var elementForRecordID: [String: AXUIElement] = [:]

    private static let cacheTTL: TimeInterval = 30
    private static let sweepDeadline: TimeInterval = 3

    /// Fraction of owned in-band items that must be Control-Center-owned
    /// before ownership data is declared untrustworthy (Tahoe re-parenting;
    /// doubles as the macOS-27 tripwire).
    private static let reparentThreshold = 0.7

    /// System agents that own extras despite a `.prohibited` policy.
    private static let systemAgentAllowlist: Set<String> = [
        "com.apple.controlcenter",
        "com.apple.TextInputMenuAgent",
        "com.apple.systemuiserver",
    ]

    // MARK: - Lifecycle

    func start() {
        guard observers.isEmpty else { return }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers = [
            (.default, NotificationCenter.default.addObserver(
                forName: .pelmetLayoutDidChange, object: nil, queue: .main
            ) { [weak self] _ in
                self?.healAttempts = 0
                self?.rebuildDirectory()
            }),
            (workspaceCenter, workspaceCenter.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
            ) { [weak self] note in
                self?.invalidateCache(for: note)
            }),
            (workspaceCenter, workspaceCenter.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
            ) { [weak self] note in
                self?.invalidateCache(for: note)
            }),
            (workspaceCenter, workspaceCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                self?.axCache.removeAll()
            }),
            (.default, NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                self?.axCache.removeAll()
            }),
        ]
        AXPermissionMonitor.shared.onChange = { [weak self] in
            self?.handleAXChange()
        }
        AXPermissionMonitor.shared.startObserving()
        // handleAXChange (not just recompute) so a grant made while awaiting —
        // including one granted before this launch — flips the engine on.
        handleAXChange()
        Self.debugTrace {
            "start: enabled=\(Preferences.activationEngineEnabled) "
                + "trusted=\(AXIsProcessTrusted()) availability=\(availability)"
        }
        rebuildDirectory()
    }

    func setEnabled(_ enabled: Bool) {
        Preferences.activationEngineEnabled = enabled
        recomputeAvailability()
    }

    func requestAccess() {
        guard Preferences.activationEngineEnabled, availability != .granted else { return }
        AXPermissionMonitor.shared.requestWithPrompt()
        recomputeAvailability()
    }

    func offerOneClick(proactive: Bool) {
        // Already trusted at the system level: just turn the feature on.
        if AXIsProcessTrusted() {
            Preferences.awaitingOneClickGrant = false
            Preferences.activationEngineEnabled = true
            recomputeAvailability()
            return
        }
        // Not proactive means an explicit tap — honor the intent to enable now;
        // the passive first-run offer keeps the engine off until the grant.
        if !proactive { Preferences.activationEngineEnabled = true }
        // Arm the enable-on-grant latch either way.
        Preferences.awaitingOneClickGrant = true
        if Preferences.didPromptForAccessibility {
            // The OS modal won't reappear once we're already listed — send the
            // user straight to the Accessibility pane instead of no-op'ing.
            AXPermissionMonitor.openSystemSettings()
        } else {
            AXPermissionMonitor.shared.requestWithPrompt()
        }
        recomputeAvailability()
    }

    func refreshDirectory(reason: String) {
        _ = reason
        rebuildDirectory()
    }

    func activate(recordID: String, completion: @escaping (ActivationResult) -> Void) {
        ActivationExecutor.shared.activate(recordID: recordID, engine: self, completion: completion)
    }

    // MARK: - Availability

    /// Fired whenever the Accessibility trust state may have changed. If we
    /// asked on the user's behalf (`awaitingOneClickGrant`) and the grant has
    /// now landed, turn one-click on — this is the only place the passive
    /// first-run flow enables the engine, since `recomputeAvailability` reports
    /// `.notDetermined` while the engine is still off.
    private func handleAXChange() {
        if Preferences.awaitingOneClickGrant, AXIsProcessTrusted() {
            Preferences.awaitingOneClickGrant = false
            Preferences.activationEngineEnabled = true
        }
        recomputeAvailability()
    }

    func recomputeAvailability() {
        let wasGranted = availability == .granted
        let newValue: ActivationAvailability
        if !Preferences.activationEngineEnabled {
            newValue = .notDetermined
        } else if AXIsProcessTrusted() {
            newValue = .granted
        } else if Preferences.didPromptForAccessibility {
            newValue = .denied
        } else {
            newValue = .notDetermined
        }
        availability = newValue
        if (newValue == .granted) != wasGranted {
            // Grant arrived or was revoked: identity and descriptors change.
            rebuildDirectory()
        }
    }

    // MARK: - Directory

    private func rebuildDirectory() {
        guard let classification = NotchLayoutMonitor.shared.confirmed else {
            elementForRecordID = [:]
            publish(.empty)
            return
        }

        let controlCenterPID = OwnerResolver.shared.controlCenterPID()
        let items = classification.items.filter {
            $0.visibility != .suspectedGhost && !$0.ownerPIDs.contains(ownPID)
        }
        let reparented = Self.isReparented(items: items, controlCenterPID: controlCenterPID)

        let cached = freshCachedObservations()
        if canActivate, !cached.isEmpty {
            // Cached FRAMES rot the moment the layout moves (every
            // collapse/expand relocates every item) — re-read each cached
            // element's live position off-main, then publish.
            refreshPositionsAndPublish(
                controlCenterPID: controlCenterPID,
                reparented: reparented,
                observations: cached
            )
        } else {
            // Free CGWindow data only; the sweep (when granted) enriches.
            publishSnapshot(
                items: items,
                controlCenterPID: controlCenterPID,
                reparented: reparented,
                observations: []
            )
        }

        if canActivate {
            scheduleSweep(controlCenterPID: controlCenterPID, reparented: reparented)
        }
    }

    /// Re-reads live positions for cached AX elements (off-main, bounded
    /// timeouts), then publishes against the latest classification.
    private func refreshPositionsAndPublish(
        controlCenterPID: Int32?,
        reparented: Bool,
        observations: [AXExtraObservation]
    ) {
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        sweepQueue.async { [weak self] in
            let refreshed = observations.map { observation in
                AXExtraObservation(
                    pid: observation.pid,
                    title: observation.title,
                    axDescription: observation.axDescription,
                    frameAppKit: LiveAXMenuBarExtrasReader.frame(
                        of: observation.element, primaryMaxY: primaryMaxY
                    ),
                    element: observation.element
                )
            }
            DispatchQueue.main.async {
                guard let self else { return }
                // Publish against the LATEST confirmed classification — the
                // layout may have moved again while positions were read.
                guard let classification = NotchLayoutMonitor.shared.confirmed else { return }
                let freshItems = classification.items.filter {
                    $0.visibility != .suspectedGhost && !$0.ownerPIDs.contains(self.ownPID)
                }
                self.publishSnapshot(
                    items: freshItems,
                    controlCenterPID: controlCenterPID,
                    reparented: reparented,
                    observations: refreshed
                )
            }
        }
    }

    private static func isReparented(items: [ClassifiedItem], controlCenterPID: Int32?) -> Bool {
        guard let controlCenterPID else { return false }
        let owned = items.filter { !$0.ownerPIDs.isEmpty }
        guard !owned.isEmpty else { return false }
        let controlCenterOnly = owned.filter { item in
            item.ownerPIDs.allSatisfy { $0 == controlCenterPID }
        }
        return Double(controlCenterOnly.count) / Double(owned.count) >= reparentThreshold
    }

    private func publishSnapshot(
        items: [ClassifiedItem],
        controlCenterPID: Int32?,
        reparented: Bool,
        observations: [AXExtraObservation]
    ) {
        let itemObservations = observations.map { observation in
            ItemObservation(
                pid: observation.pid,
                title: observation.title ?? observation.axDescription,
                frame: observation.frameAppKit
            )
        }
        let correlated = StatusItemCorrelator.correlate(
            classified: items, observed: itemObservations
        )

        var records: [MenuBarItemRecord] = []
        var elements: [String: AXUIElement] = [:]
        var identifiedAny = false

        for pair in correlated {
            let item = pair.item
            var identity: ItemIdentity?

            // AX observation wins (it has titles and survives Tahoe);
            // CGWindow ownership is the free fallback where trustworthy.
            var identityPID: Int32?
            if let observation = pair.observation {
                identityPID = observation.pid
            } else if !reparented {
                identityPID = item.ownerPIDs.first { $0 != controlCenterPID }
            }

            if let pid = identityPID,
               let info = OwnerResolver.shared.info(for: pid),
               let name = info.localizedName ?? info.bundleID {
                identity = ItemIdentity(
                    pid: pid,
                    bundleIdentifier: info.bundleID,
                    appName: name,
                    axTitle: TitleHygiene.meaningfulTitle(
                        pair.observation?.title,
                        appName: name,
                        bundleID: info.bundleID
                    )
                )
                identifiedAny = true
            }

            let record = MenuBarItemRecord(
                frame: item.frame,
                visibility: item.visibility,
                identity: identity
            )
            records.append(record)

            // itemObservations is index-aligned with `observations`, so the
            // matched value maps straight back to its live AX element.
            if let observation = pair.observation,
               let index = itemObservations.firstIndex(of: observation) {
                elements[record.id] = observations[index].element
            }
        }

        elementForRecordID = elements
        Self.debugTrace {
            let described = records.map { record -> String in
                let who = record.identity.map { "\($0.appName)(\($0.pid))" } ?? "?"
                return "[\(Int(record.frame.minX)),\(Int(record.frame.maxX))] \(record.visibility) → \(who)"
            }
            return "directory: reparented=\(reparented) observations=\(observations.count) "
                + "records=\(records.count)\n  " + described.joined(separator: "\n  ")
        }
        publish(DirectorySnapshot(
            records: records,
            fidelity: identifiedAny ? .identified : .framesOnly,
            capturedAt: Date()
        ))

        // Self-heal: a swallowed row without identity is the user-visible
        // failure ("Hidden item N", no logo). When it's a transient (element
        // positions read mid-animation), a re-read moments later fixes it.
        let unidentifiedSwallowed = records.contains {
            $0.visibility == .swallowedByNotch && $0.identity == nil
        }
        if canActivate, unidentifiedSwallowed, !axCache.isEmpty, healAttempts < 2 {
            healAttempts += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.rebuildDirectory()
            }
        }
    }

    private func publish(_ snapshot: DirectorySnapshot) {
        directory = snapshot
        onDirectoryChange?(snapshot)
    }

    // MARK: - AX sweep

    private func freshCachedObservations() -> [AXExtraObservation] {
        let now = Date()
        return axCache.values
            .filter { now.timeIntervalSince($0.stamp) < Self.cacheTTL }
            .flatMap(\.observations)
    }

    private func invalidateCache(for note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            axCache.removeAll()
            return
        }
        axCache.removeValue(forKey: app.processIdentifier)
    }

    private func scheduleSweep(controlCenterPID: Int32?, reparented: Bool) {
        guard !isSweeping else { return }
        isSweeping = true
        sweepGeneration += 1
        let generation = sweepGeneration

        // Everything AppKit-derived is captured on main before hopping off.
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        let staleCutoff = Date().addingTimeInterval(-Self.cacheTTL)
        let cachedPIDs = Set(axCache.filter { $0.value.stamp > staleCutoff }.keys)
        let candidates = sweepCandidates().filter { !cachedPIDs.contains($0) }
        guard !candidates.isEmpty else {
            isSweeping = false
            return
        }
        let reader = extrasReader
        let slow = slowPIDs

        sweepQueue.async { [weak self] in
            let deadline = Date().addingTimeInterval(Self.sweepDeadline)
            var results: [pid_t: [AXExtraObservation]] = [:]
            var newSlow: Set<pid_t> = []

            // Previously slow apps go last so they can only eat the tail of
            // the budget.
            let ordered = candidates.sorted { slow.contains($0) ? false : slow.contains($1) }
            for pid in ordered {
                guard Date() < deadline else { break }
                let start = Date()
                results[pid] = reader.extras(forPID: pid, primaryMaxY: primaryMaxY)
                if Date().timeIntervalSince(start) > 0.9 { newSlow.insert(pid) }
            }
            let attemptedAll = results.count == ordered.count

            DispatchQueue.main.async {
                guard let self else { return }
                self.isSweeping = false
                guard generation == self.sweepGeneration else { return }
                let stamp = Date()
                for (pid, observations) in results {
                    self.axCache[pid] = (observations, stamp)
                }
                self.slowPIDs.formUnion(newSlow)
                Self.debugTrace {
                    let found = results.filter { !$0.value.isEmpty }
                    return "AX sweep: attempted \(results.count)/\(ordered.count) apps, "
                        + "\(found.count) with extras (\(found.values.map(\.count).reduce(0, +)) items)"
                        + (attemptedAll ? "" : " (continuing)")
                }

                // Route back through rebuildDirectory: it refreshes cached
                // element positions, publishes, and — because swept PIDs are
                // now cached — schedules the NEXT pass only while unswept
                // candidates remain (one 3s pass can't cover a busy Mac's
                // app list; each pass caches ≥1 PID, so this terminates).
                guard !results.isEmpty else { return }
                self.rebuildDirectory()
            }
        }
    }

    /// stdout tracing for `swift run` users, mirroring PELMET_DEBUG_LAYOUT.
    static func debugTrace(_ message: () -> String) {
        guard ProcessInfo.processInfo.environment["PELMET_DEBUG_ACTIVATION"] != nil else { return }
        print("Pelmet activation: \(message())")
        fflush(stdout)
    }

    /// Apps that could plausibly own a menu bar extra. `kAXExtrasMenuBar`
    /// is per-app, cannot see our own extras, and some LSUIElement apps
    /// expose nothing — those fall back to CGWindow/frame data.
    private func sweepCandidates() -> [pid_t] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard !app.isTerminated, app.processIdentifier != ownPID else { return nil }
            switch app.activationPolicy {
            case .regular, .accessory:
                return app.processIdentifier
            case .prohibited:
                guard let bundleID = app.bundleIdentifier,
                      Self.systemAgentAllowlist.contains(bundleID) else { return nil }
                return app.processIdentifier
            @unknown default:
                return nil
            }
        }
    }
}
