import AppKit
import Combine
import Foundation
import PelmetCore

enum UpdaterStatus: Equatable {
    case unavailable
    case idle(lastSuccessfulCheck: Date?)
    case checking
    case waitingForNetwork
    case retryScheduled(Date)
    case failed
    case updateAvailable(version: String)

    var availableVersion: String? {
        guard case let .updateAvailable(version) = self else { return nil }
        return version
    }

    var settingsText: String {
        switch self {
        case .unavailable:
            return "Software Update is available in the bundled app."
        case let .idle(lastSuccessfulCheck):
            guard let lastSuccessfulCheck else {
                return "Updates are checked daily after you opt in."
            }
            let formatter = RelativeDateTimeFormatter()
            formatter.dateTimeStyle = .named
            let relative = formatter.localizedString(for: lastSuccessfulCheck, relativeTo: Date())
            return "Last checked \(relative)."
        case .checking:
            return "Checking for updates…"
        case .waitingForNetwork:
            return "Offline — retrying when connected."
        case let .retryScheduled(date):
            let formatter = RelativeDateTimeFormatter()
            formatter.dateTimeStyle = .named
            let relative = formatter.localizedString(for: date, relativeTo: Date())
            return "Update check failed — retrying \(relative)."
        case .failed:
            return "Update check failed — try again."
        case let .updateAvailable(version):
            return "Update \(version) is available."
        }
    }
}

/// Thin facade over Sparkle plus Pelmet's bounded network-failure recovery and
/// menu-bar-friendly update reminder state.
///
/// The type exists in every build so call sites never need their own `#if`.
/// Sparkle is embedded only in the XcodeGen `.app`; `swift run` and tests use
/// the inert implementation at the bottom of this file.
#if canImport(Sparkle)
import Network
import Sparkle

final class UpdaterController: NSObject, ObservableObject {
    static let shared = UpdaterController()

    @Published private(set) var status: UpdaterStatus

    var isAvailable: Bool { true }
    var availableVersion: String? { status.availableVersion }

    private var controller: SPUStandardUpdaterController!
    private var retryCoordinator: UpdateRetryCoordinator
    private var retryTimer: Timer?
    private var pathMonitor: NWPathMonitor?
    private var connectivityAvailable: Bool?
    private var automaticChecksObservation: NSKeyValueObservation?

    private override init() {
        retryCoordinator = UpdateRetryCoordinator(snapshot: Preferences.updateRetrySnapshot)
        status = .idle(lastSuccessfulCheck: Preferences.lastSuccessfulUpdateCheck)
        super.init()

        // Both delegates are weakly held by Sparkle, so this singleton owns the
        // updater controller and acts as the retained delegate for its lifetime.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )

        automaticChecksObservation = controller.updater.observe(
            \SPUUpdater.automaticallyChecksForUpdates,
            options: [.new]
        ) { [weak self] _, change in
            DispatchQueue.main.async {
                guard let enabled = change.newValue else { return }
                self?.automaticCheckPreferenceChanged(enabled)
            }
        }
        automaticCheckPreferenceChanged(controller.updater.automaticallyChecksForUpdates)
    }

    @objc func checkForUpdates(_ sender: Any?) {
        if availableVersion == nil {
            status = .checking
        }
        controller.checkForUpdates(sender)
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set {
            controller.updater.automaticallyChecksForUpdates = newValue
            automaticCheckPreferenceChanged(newValue)
        }
    }

    private func automaticCheckPreferenceChanged(_ enabled: Bool) {
        if enabled {
            startConnectivityMonitoring()
        } else {
            retryCoordinator.clear()
            syncRetryState(effect: .none)
            stopConnectivityMonitoring()
            status = .idle(lastSuccessfulCheck: Preferences.lastSuccessfulUpdateCheck)
        }
    }

    // MARK: - Connectivity and retry scheduling

    private func startConnectivityMonitoring() {
        guard pathMonitor == nil else { return }
        connectivityAvailable = nil

        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.connectivityDidChange(path.status == .satisfied)
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.ismatbabirli.Pelmet.update-connectivity"))
    }

    private func stopConnectivityMonitoring() {
        pathMonitor?.cancel()
        pathMonitor = nil
        connectivityAvailable = nil
    }

    private func connectivityDidChange(_ available: Bool) {
        let wasKnown = connectivityAvailable != nil
        connectivityAvailable = available

        let effect: UpdateRetryEffect
        if wasKnown {
            effect = retryCoordinator.connectivityChanged(available: available, now: Date())
        } else {
            effect = retryCoordinator.resume(
                now: Date(),
                connectivityAvailable: available,
                automaticallyChecks: automaticallyChecksForUpdates
            )
        }
        syncRetryState(effect: effect)
    }

    private func syncRetryState(effect: UpdateRetryEffect) {
        Preferences.updateRetrySnapshot = retryCoordinator.snapshot
        retryTimer?.invalidate()
        retryTimer = nil

        switch retryCoordinator.phase {
        case .inactive:
            break
        case .waitingForConnectivity:
            status = .waitingForNetwork
        case let .scheduled(date):
            status = .retryScheduled(date)
            let delay = max(0.05, date.timeIntervalSinceNow)
            retryTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                self?.retryTimerDidFire()
            }
        case .checking:
            status = .checking
        }

        switch effect {
        case .none:
            break
        case .performRetry:
            status = .checking
            controller.updater.checkForUpdatesInBackground()
        case .exhausted:
            status = .failed
        }
    }

    private func retryTimerDidFire() {
        let effect = retryCoordinator.retryTimerFired(
            now: Date(),
            updaterCanCheck: controller.updater.canCheckForUpdates
        )
        syncRetryState(effect: effect)
    }

    private func recordSuccessfulCheck() {
        let now = Date()
        Preferences.lastSuccessfulUpdateCheck = now
        retryCoordinator.clear()
        syncRetryState(effect: .none)
        status = .idle(lastSuccessfulCheck: now)
    }

    private func handleBackgroundFailure(_ error: Error) {
        guard isTransientNetworkError(error) else {
            retryCoordinator.clear()
            syncRetryState(effect: .none)
            status = .failed
            return
        }

        let effect = retryCoordinator.recordNetworkFailure(
            now: Date(),
            connectivityAvailable: connectivityAvailable ?? false
        )
        syncRetryState(effect: effect)
    }

    private func isTransientNetworkError(_ error: Error, depth: Int = 0) -> Bool {
        guard depth < 10 else { return false }
        let nsError = error as NSError
        let transientCodes: Set<Int> = [
            URLError.Code.notConnectedToInternet.rawValue,
            URLError.Code.networkConnectionLost.rawValue,
            URLError.Code.timedOut.rawValue,
            URLError.Code.cannotFindHost.rawValue,
            URLError.Code.cannotConnectToHost.rawValue,
            URLError.Code.dnsLookupFailed.rawValue,
        ]
        if nsError.domain == NSURLErrorDomain, transientCodes.contains(nsError.code) {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error,
           isTransientNetworkError(underlying, depth: depth + 1) {
            return true
        }
        if let errors = nsError.userInfo["NSMultipleUnderlyingErrors"] as? [Error] {
            return errors.contains { isTransientNetworkError($0, depth: depth + 1) }
        }
        return false
    }
}

// MARK: - Sparkle delegates

extension UpdaterController: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let now = Date()
        Preferences.lastSuccessfulUpdateCheck = now
        retryCoordinator.clear()
        syncRetryState(effect: .none)
        status = .updateAvailable(version: item.displayVersionString)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        // Sparkle reports an ordinary "already current" result through its
        // error-shaped no-update path. It still proves the feed was reached.
        let nsError = error as NSError
        if nsError.domain == SUSparkleErrorDomain,
           nsError.code == SUError.noUpdateError.rawValue {
            recordSuccessfulCheck()
        }
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        if let error {
            let nsError = error as NSError
            if nsError.domain == SUSparkleErrorDomain,
               nsError.code == SUError.noUpdateError.rawValue {
                recordSuccessfulCheck()
            } else if updateCheck == .updatesInBackground {
                handleBackgroundFailure(error)
            } else if retryCoordinator.phase == .inactive {
                status = .failed
            } else {
                // A manual check may happen while recovery is pending. Its
                // failure must not erase or advance that background episode.
                syncRetryState(effect: .none)
            }
            // User-initiated errors are presented by Sparkle and never create
            // or advance a background retry episode.
            return
        }

        if availableVersion == nil {
            recordSuccessfulCheck()
        }
    }
}

extension UpdaterController: SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        // The persistent menu-bar cue owns scheduled discovery. A user click on
        // that cue calls checkForUpdates and brings Sparkle's standard UI front.
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard !handleShowingUpdate, !state.userInitiated else { return }
        status = .updateAvailable(version: update.displayVersionString)
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        status = .idle(lastSuccessfulCheck: Preferences.lastSuccessfulUpdateCheck)
    }

    func standardUserDriverWillFinishUpdateSession() {
        status = .idle(lastSuccessfulCheck: Preferences.lastSuccessfulUpdateCheck)
    }
}
#else
final class UpdaterController: ObservableObject {
    static let shared = UpdaterController()

    @Published private(set) var status: UpdaterStatus = .unavailable
    var isAvailable: Bool { false }
    var availableVersion: String? { nil }

    private init() {}
    @objc func checkForUpdates(_ sender: Any?) {}
    var automaticallyChecksForUpdates: Bool {
        get { false }
        set {}
    }
}
#endif
