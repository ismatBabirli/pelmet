import AppKit
import os
import PelmetCore

/// Sends Pelmet's one anonymous event: a daily "heartbeat". Modeled on
/// `UpdaterController` (a thin singleton started from
/// `applicationDidFinishLaunching`) and, like it, inert unless it is a real
/// release build the user has been told about.
///
/// Everything that decides *whether* to send lives in `PelmetCore`
/// (`TelemetryGate`, `HeartbeatSchedule`) and is unit-tested; this type only
/// gathers inputs, builds the payload, and does the network I/O. It has no
/// reference to the Shelf or `NSRunningApplication`, so a user's menu bar
/// contents cannot reach the wire.
final class TelemetryManager {

    static let shared = TelemetryManager()

    /// PostHog project API key. This is a PUBLIC, write-only ingestion token
    /// (it can only send events, never read data back), so it is safe to embed
    /// in open-source source. The "Pelmet" project on PostHog Cloud US has
    /// "Discard client IP data" enabled. The `phc_REPLACE` sentinel below keeps
    /// `isConfigured` false (and stops all sends) if the key is ever cleared.
    private static let apiKey = "phc_tpzRsgpnvLvi8WZrY8N6XJw3kaNNNsXQJ6qAnjS9XBqS"
    private static let endpoint = URL(string: "https://us.i.posthog.com/i/v0/e/")!

    private static var isConfigured: Bool { !apiKey.hasPrefix("phc_REPLACE") }

    #if DEBUG
    private static let isDebugBuild = true
    #else
    private static let isDebugBuild = false
    #endif

    private let log = Logger(subsystem: "com.ismatbabirli.Pelmet", category: "Telemetry")

    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    /// True only if the first-run notice was shown during THIS process, which
    /// arms the cooling-off hold on the very first send.
    private var noticeShownThisSession = false
    /// The UTC day of a send that is currently in flight, reserved synchronously
    /// on the main thread before the request starts. The persisted last-sent day
    /// only updates when the request completes, so without this two overlapping
    /// `checkNow()` calls (e.g. the launch check and a wake) could both see the
    /// day as due and double-send. Only ever touched on the main thread.
    private var inFlightHeartbeatDay: String?

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral // no cookies, no cache
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = false // fail fast; the next tick retries
        return URLSession(configuration: config)
    }()

    private init() {}

    // MARK: - Lifecycle

    /// Schedules checks only; never blocks launch and never sends synchronously.
    func start() {
        scheduleTimer()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.checkNow()
        }
        // A missed repeating-timer fire during sleep is covered by the wake
        // observer; the launch delay keeps us off the network during login.
        DispatchQueue.main.asyncAfter(deadline: .now() + HeartbeatSchedule.launchDelay) { [weak self] in
            self?.checkNow()
        }
    }

    private func scheduleTimer() {
        let timer = Timer(timeInterval: HeartbeatSchedule.recheckInterval, repeats: true) { [weak self] _ in
            self?.checkNow()
        }
        timer.tolerance = 300 // generous: the send decision is idempotent per day
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - Consent / settings

    /// Whether the first-run notice should be offered (used by the onboarding
    /// chain). False in dev/debug builds, under DO_NOT_TRACK, or once shown.
    var needsFirstRunNotice: Bool { TelemetryGate.shouldOfferNotice(gateInputs) }

    /// Called when the first-run notice has actually been shown. Burns the flag
    /// and starts the cooling-off window; does not send now.
    func recordNoticeShown() {
        Preferences.didShowTelemetryNotice = true
        Preferences.telemetryNoticeShownAt = Date()
        noticeShownThisSession = true
    }

    var isEnabled: Bool { Preferences.telemetryEnabled }

    /// The Settings toggle target. Persists the preference and, on opt-out,
    /// forgets the install ID so re-enabling starts a fresh, unlinkable identity.
    func setEnabled(_ enabled: Bool) {
        Preferences.telemetryEnabled = enabled
        if enabled {
            checkNow()
        } else {
            Preferences.telemetryInstallID = nil
        }
    }

    /// "Reset Install ID" in Settings: a new random identifier, unlinkable from
    /// past pings.
    func resetInstallID() {
        Preferences.telemetryInstallID = UUID().uuidString
    }

    /// The exact JSON that would be sent right now, for the Settings "what is
    /// sent" disclosure. Uses the persisted install ID, or a zeroed placeholder
    /// when none exists yet (so the preview never mints an ID as a side effect).
    func currentPreviewJSON() -> String {
        let id = Preferences.telemetryInstallID ?? "00000000-0000-0000-0000-000000000000"
        return makePayload(distinctID: id).previewJSON(apiKey: Self.apiKey)
    }

    // MARK: - Sending

    func checkNow() {
        let verbose = ProcessInfo.processInfo.environment["PELMET_DEBUG_TELEMETRY"] == "verbose"
        let now = Date()
        let active = TelemetryGate.isActive(gateInputs)
        let coolingElapsed = HeartbeatSchedule.coolingOffElapsed(
            noticeShownThisSession: noticeShownThisSession,
            noticeShownAt: Preferences.telemetryNoticeShownAt,
            now: now
        )
        let due = HeartbeatSchedule.shouldSend(
            lastSentDay: Preferences.telemetryLastHeartbeatDay, now: now
        )

        if verbose {
            let id = Preferences.telemetryInstallID ?? "<generated at first send>"
            print("""
            Pelmet telemetry (dry run): active=\(active) configured=\(Self.isConfigured) \
            coolingOffElapsed=\(coolingElapsed) dueToday=\(due)
            \(makePayload(distinctID: id).previewJSON(apiKey: Self.apiKey))
            """)
            fflush(stdout)
        }

        guard Self.isConfigured, active, coolingElapsed, due,
              inFlightHeartbeatDay != HeartbeatSchedule.dayKey(for: now) else { return }
        send(makePayload(distinctID: installIDForSend()))
    }

    private func send(_ payload: TelemetryPayload) {
        guard let body = try? payload.postHogBody(apiKey: Self.apiKey) else { return }
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        // Reserve the day synchronously (on main) before the request starts, so a
        // second checkNow() during the round trip sees it as taken. On completion,
        // a success promotes it to the persisted last-sent day; either way the
        // reservation is released so the next day can send.
        let day = HeartbeatSchedule.dayKey(for: payload.timestamp)
        inFlightHeartbeatDay = day
        session.dataTask(with: request) { [weak self] _, response, error in
            let succeeded = error == nil
                && (response as? HTTPURLResponse).map { (200 ..< 300).contains($0.statusCode) } ?? false
            DispatchQueue.main.async {
                if succeeded {
                    Preferences.telemetryLastHeartbeatDay = day
                    self?.log.debug("heartbeat sent")
                } else {
                    // Fail totally silently: a blocked endpoint (Little Snitch,
                    // Pi-hole) is a no-op, and the next tick is the only retry.
                    self?.log.debug("heartbeat send did not complete; will retry next tick")
                }
                if self?.inFlightHeartbeatDay == day {
                    self?.inFlightHeartbeatDay = nil
                }
            }
        }.resume()
    }

    // MARK: - Inputs

    private var gateInputs: TelemetryGate.Inputs {
        let env = ProcessInfo.processInfo.environment
        return TelemetryGate.Inputs(
            enabledPreference: Preferences.telemetryEnabled,
            noticeShown: Preferences.didShowTelemetryNotice,
            isDevelopmentBuild: AppVersionInfo.current.isDevelopmentBuild,
            isDebugBuild: Self.isDebugBuild,
            doNotTrack: env["DO_NOT_TRACK"],
            disableOverride: env["PELMET_DISABLE_TELEMETRY"],
            forceOverride: env["PELMET_FORCE_TELEMETRY"]
        )
    }

    private func installIDForSend() -> String {
        if let existing = Preferences.telemetryInstallID { return existing }
        let new = UUID().uuidString
        Preferences.telemetryInstallID = new
        return new
    }

    private func makePayload(distinctID: String) -> TelemetryPayload {
        TelemetryPayload(
            distinctID: distinctID,
            timestamp: Date(),
            appVersion: AppVersionInfo.current.shortVersion ?? AppVersion.developmentBuild,
            macOS: Self.macOSVersionString,
            arch: Self.archString,
            notch: LayoutStatus.shared.hasNotchedDisplay,
            shelfEnabled: Preferences.shelfEnabled,
            oneClickEnabled: Preferences.activationEngineEnabled,
            autoRehide: Preferences.autoRehide,
            managesItems: Preferences.hasEverManagedItems,
            prevSessionClean: CrashReportMonitor.shared.previousSessionEndedCleanly
        )
    }

    private static var macOSVersionString: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion)"
    }

    private static var archString: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}
