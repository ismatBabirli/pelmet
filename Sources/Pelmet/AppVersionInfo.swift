import AppKit
import PelmetCore

/// Reads `Bundle.main`'s version/copyright keys and hands them to the pure
/// `AppVersion` formatter. Every key is nil under `swift run` (the SPM
/// executable has no Info.plist), so `AppVersion` collapses to its
/// "Development build" state. No `#if` needed here, the reads just return nil.
enum AppVersionInfo {

    /// The current version, formatted for display. Routed through here (never
    /// raw `Bundle` keys) so the `swift run` fallback lives in one place.
    static var current: AppVersion {
        let info = Bundle.main.infoDictionary
        return AppVersion(
            shortVersion: info?["CFBundleShortVersionString"] as? String,
            build: info?["CFBundleVersion"] as? String
        )
    }

    /// `NSHumanReadableCopyright` ("MIT License" in the bundle), falling back to
    /// the same literal under `swift run`: Pelmet is MIT-licensed in every build.
    static var copyright: String {
        let raw = (Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (raw?.isEmpty == false ? raw : nil) ?? "MIT License"
    }
}

/// Open-source destinations for the About pane. The owner casing matches the
/// compare links already in `CHANGELOG.md`; GitHub is case-insensitive on it.
enum AppLinks {
    static let repo = URL(string: "https://github.com/ismatBabirli/pelmet")!
    static let releases = URL(string: "https://github.com/ismatBabirli/pelmet/releases")!
    static let issues = URL(string: "https://github.com/ismatBabirli/pelmet/issues/new")!
    /// Full field-by-field telemetry disclosure. Linked from the first-run
    /// notice and the Settings Privacy section.
    static let telemetryDoc = URL(string: "https://github.com/ismatBabirli/pelmet/blob/main/docs/TELEMETRY.md")!
}
