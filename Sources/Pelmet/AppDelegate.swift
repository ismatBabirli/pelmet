import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as a menu-bar-only app (no Dock icon, no main window).
        NSApp.setActivationPolicy(.accessory)

        // Refuse to launch a second copy: two instances each add a toggle +
        // separator and both inflate a 10,000 pt spacer, shoving each other's
        // items off-screen so every chevron looks dead. The lock is released
        // automatically when this process exits. See acquireSingleInstanceLock.
        guard Self.acquireSingleInstanceLock() else {
            print("Another copy of Pelmet is already running. Quitting this one.")
            fflush(stdout)
            NSApp.terminate(nil)
            return
        }

        // Sample the app domain before menu setup seeds status-item positions.
        // That is the only reliable way to distinguish a truly fresh install
        // from an existing user receiving the first What's New-enabled release.
        let hadExistingPreferences = Preferences.hasPersistentApplicationPreferences
        WhatsNewWindowController.shared.prepareAutomaticPresentation(
            hadExistingPreferences: hadExistingPreferences
        )

        MenuBarManager.shared.setUp()

        // Start Sparkle (bundled .app only). Sparkle asks the user once on
        // first launch whether to check automatically; nothing hits the network
        // until they opt in. Inert under `swift run` (no bundle, no Sparkle).
        _ = UpdaterController.shared

        // Local-only crash follow-up: captures the clean-exit sentinel first,
        // then (if the last session crashed) offers a prefilled GitHub issue.
        // No trace is ever uploaded.
        CrashReportMonitor.shared.checkOnLaunch()

        // Anonymous daily usage ping. Schedules only; sends nothing until the
        // first-run notice is shown, and stays inert under `swift run`/DEBUG.
        TelemetryManager.shared.start()

        // Global hotkeys: ⌥⌘B toggles hidden items, ⌥⌘N opens the Shelf.
        HotkeyManager.shared.onToggle = {
            MenuBarManager.shared.toggle()
        }
        HotkeyManager.shared.onShelf = {
            MenuBarManager.shared.openShelfFromHotkey()
        }
        let registration = HotkeyManager.shared.register()

        printStartupBanner(hotkeys: registration)

        // Let applicationDidFinishLaunching return before taking focus. The
        // controller waits if Sparkle happens to own a modal at this point.
        DispatchQueue.main.async {
            WhatsNewWindowController.shared.presentPreparedIfNeeded()
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    /// Record a clean shutdown so the next launch doesn't mistake this quit for
    /// a crash. SIGINT/SIGTERM are handled separately in CrashReportMonitor.
    func applicationWillTerminate(_ notification: Notification) {
        CrashReportMonitor.shared.markCleanExit()
    }

    /// HIG: "avoid relying on the presence of menu bar extras." If the user
    /// can't find Pelmet in the bar at all, launching it again from Finder,
    /// Spotlight or the Dock lands here — open Settings as the escape hatch.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return false
    }

    /// Ensures only one Pelmet runs at a time. An advisory file lock works across
    /// both a bundled `.app` and `swift run` (which has no bundle id, so
    /// `NSRunningApplication` bundle-id checks miss it), and the kernel releases
    /// it automatically when the process exits — even on crash — so no stale lock
    /// can wedge future launches.
    private static func acquireSingleInstanceLock() -> Bool {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("com.ismatbabirli.Pelmet.single-instance.lock")
        let fd = open(path, O_CREAT | O_RDWR, 0o644)
        guard fd != -1 else { return true }  // fail open: never block startup on a lock error
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            return false
        }
        // Deliberately keep `fd` open for the process lifetime to hold the lock.
        return true
    }

    /// Terminal feedback for `swift run` users — the only way to tell an
    /// invisible menu-bar app is alive. A bundled .app has no visible stdout,
    /// and os.Logger goes to the unified log, not the terminal, so print is
    /// the right channel for this audience.
    private func printStartupBanner(hotkeys: HotkeyManager.Registration) {
        var lines = [
            "Pelmet is running as a menu-bar-only app (no Dock icon, no window).",
            "  Look for the ‹/› chevron toggle next to the clock; the ╱ divider",
            "  sits just left of the chevron.",
            hotkeys.toggle
                ? "  • Click the chevron or press ⌥⌘B to hide/show icons."
                : "  • Click the chevron to hide/show icons. (⌥⌘B is unavailable; another app claimed it.)",
            "  • Pelmet hides everything LEFT of ╱. ⌘-drag icons you always",
            "    want visible to its RIGHT, next to the clock.",
        ]
        if Preferences.autoRehide {
            lines.append("  • Revealed icons re-hide after \(Int(Preferences.rehideDelay)) s (right-click the chevron → Settings).")
        }
        lines.append(contentsOf: [
            "  • A number next to the chevron (like +3) means that many icons don't fit",
            "    beside the notch. Click the chevron to see them on the Shelf"
                + (hotkeys.shelf ? " (or press ⌥⌘N)." : "."),
            "  • Can't find Pelmet in the bar? Launching it again opens its Settings window.",
            "  • Ctrl-C here (or closing this terminal) quits Pelmet.",
        ])
        print(lines.joined(separator: "\n"))
        // stdout is block-buffered when redirected (pipe/file); flush so the
        // banner isn't held back until the app exits.
        fflush(stdout)
    }
}
