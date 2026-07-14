import AppKit
import os
import PelmetCore

/// Local-only crash follow-up. Pelmet never uploads a crash report: this type
/// only notices that the previous session ended uncleanly, offers to open a
/// prefilled GitHub issue the user reviews and submits themselves, and reveals
/// the system `.ips` report in Finder so they can attach it if they choose.
///
/// It also owns the clean-exit sentinel that feeds the heartbeat's single
/// `prev_session_clean` boolean (the entire crash signal in telemetry: a
/// boolean, never a trace).
final class CrashReportMonitor {

    static let shared = CrashReportMonitor()

    private let log = Logger(subsystem: "com.ismatbabirli.Pelmet", category: "CrashReport")

    /// Captured once at launch, before the sentinel is flipped, so both the
    /// crash prompt and `TelemetryManager` read a stable value. Defaults to
    /// true so a brand-new install is never treated as a crash.
    private(set) var previousSessionEndedCleanly = true

    private var signalSources: [DispatchSourceSignal] = []

    private init() {}

    // MARK: - Lifecycle

    /// Reads the sentinel (how the last session ended), re-arms it for this
    /// session, and, if the last session crashed, offers the report prompt.
    /// The capture is synchronous so ordering against `TelemetryManager.start()`
    /// does not matter.
    func checkOnLaunch() {
        previousSessionEndedCleanly = Preferences.lastSessionCleanExit
        Preferences.lastSessionCleanExit = false
        installCleanExitSignalHandlers()

        guard !previousSessionEndedCleanly else { return }
        log.debug("previous session ended uncleanly")
        guard !Preferences.crashPromptDisabled else { return }

        // Defer the alert so it never lands during the launch storm; onboarding
        // popovers retry, so ordering with them is safe.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.presentCrashPrompt()
        }
    }

    /// Marks this session as having ended cleanly. Called from
    /// `applicationWillTerminate` and from the SIGINT/SIGTERM handlers, so a
    /// normal quit, a Ctrl-C under `swift run`, and a logout-time SIGTERM are
    /// all distinguished from an actual crash.
    func markCleanExit() {
        Preferences.lastSessionCleanExit = true
    }

    /// A clean SIGINT/SIGTERM never counts as a crash. `SIG_IGN` defuses the
    /// default terminate; the dispatch source then records a clean exit and
    /// quits. Without this, every Ctrl-C under `swift run` (and every logout)
    /// would look like a crash on the next launch.
    private func installCleanExitSignalHandlers() {
        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                self?.markCleanExit()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    // MARK: - Reporting

    /// About pane "Report a Problem": open a prefilled issue with environment
    /// info. No crash report is involved on this path.
    func reportProblem() {
        NSWorkspace.shared.open(issueURL())
    }

    private func presentCrashPrompt() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Pelmet quit unexpectedly last time"
        alert.informativeText = "Sorry about that. Crash details stay on your Mac; Pelmet "
            + "never sends them anywhere. If you have a minute, Pelmet can open a GitHub "
            + "issue prefilled with your Pelmet and macOS versions, and show you the crash "
            + "report so you can look it over and attach it yourself."
        alert.addButton(withTitle: "Report a Problem…")
        alert.addButton(withTitle: "Not Now")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't offer this after future crashes"

        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            Preferences.crashPromptDisabled = true
        }
        guard response == .alertFirstButtonReturn else { return }

        if let report = newestCrashReport() {
            NSWorkspace.shared.activateFileViewerSelecting([report])
        }
        NSWorkspace.shared.open(issueURL())
    }

    /// Newest `Pelmet-*.ips` in the top level of DiagnosticReports (aged-out
    /// reports move to a `Retired/` subfolder, which we skip). Read failures
    /// degrade to nil: the issue still opens, just without the Finder reveal.
    private func newestCrashReport() -> URL? {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return nil }

        return entries
            .filter { $0.lastPathComponent.hasPrefix("Pelmet-") && $0.pathExtension == "ips" }
            .max { modificationDate($0) < modificationDate($1) }
    }

    private func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
    }

    /// A prefilled bug-report form URL. Query keys match the field `id`s in
    /// `.github/ISSUE_TEMPLATE/bug_report.yml`; the "what happened" field stays
    /// empty for the user to fill.
    private func issueURL() -> URL {
        var components = URLComponents(url: AppLinks.issues, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "template", value: "bug_report.yml"),
            URLQueryItem(name: "labels", value: "bug"),
            URLQueryItem(name: "version", value: AppVersionInfo.current.displayValue),
            URLQueryItem(name: "environment", value: Self.environmentDescription),
        ]
        return components?.url ?? AppLinks.issues
    }

    /// "macOS 15.5, arm64, notched display" style summary for the prefill.
    private static var environmentDescription: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let macOS = "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        #if arch(arm64)
        let arch = "arm64"
        #elseif arch(x86_64)
        let arch = "x86_64"
        #else
        let arch = "unknown"
        #endif
        let notch = LayoutStatus.shared.hasNotchedDisplay ? ", notched display" : ""
        return "\(macOS), \(arch)\(notch)"
    }
}
