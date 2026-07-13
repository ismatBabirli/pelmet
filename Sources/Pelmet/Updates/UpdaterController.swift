import AppKit

/// Thin facade over Sparkle's `SPUStandardUpdaterController`.
///
/// The type exists in every build so call sites (menu, Settings) never need
/// their own `#if`. Sparkle is embedded only in the XcodeGen `.app` build
/// (see `project.yml`), so under `swift run` / SPM `canImport(Sparkle)` is
/// false and this collapses to an inert stub whose `isAvailable` is `false`.
/// The updater only works from a signed bundle anyway, so there's nothing to
/// run without one — the same way launch-at-login degrades under `swift run`.
#if canImport(Sparkle)
import Sparkle

final class UpdaterController {
    static let shared = UpdaterController()

    /// True in the bundled app: the "Check for Updates…" menu item and the
    /// Software Update settings section show themselves off this.
    var isAvailable: Bool { true }

    // Starts the updater on init; retained for the process lifetime via the
    // shared singleton so scheduled checks keep running.
    private let controller: SPUStandardUpdaterController

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// Presents Sparkle's update UI (menu item / Settings button action).
    @objc func checkForUpdates(_ sender: Any?) {
        controller.checkForUpdates(sender)
    }

    /// Bridges Sparkle's own "check automatically" preference to the Settings
    /// toggle. Sparkle persists it under its own defaults — no `Preferences` key.
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
}
#else
final class UpdaterController {  // Sparkle absent (swift run / SPM / tests).
    static let shared = UpdaterController()
    var isAvailable: Bool { false }
    private init() {}
    @objc func checkForUpdates(_ sender: Any?) {}
    var automaticallyChecksForUpdates: Bool {
        get { false }
        set {}
    }
}
#endif
