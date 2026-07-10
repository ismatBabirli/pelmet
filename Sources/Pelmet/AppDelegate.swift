import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as a menu-bar-only app (no Dock icon, no main window).
        NSApp.setActivationPolicy(.accessory)

        MenuBarManager.shared.setUp()

        // Global hotkey: ⌥⌘B toggles hidden items.
        HotkeyManager.shared.onToggle = {
            MenuBarManager.shared.toggle()
        }
        let hotkeyRegistered = HotkeyManager.shared.register()

        printStartupBanner(hotkeyRegistered: hotkeyRegistered)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    /// Terminal feedback for `swift run` users — the only way to tell an
    /// invisible menu-bar app is alive. A bundled .app has no visible stdout,
    /// and os.Logger goes to the unified log, not the terminal, so print is
    /// the right channel for this audience.
    private func printStartupBanner(hotkeyRegistered: Bool) {
        var lines = [
            "Pelmet is running as a menu-bar-only app (no Dock icon, no window).",
            "  Look for the ‹/› chevron toggle next to the clock; the ╱ divider",
            "  sits at the left end of your menu bar icons.",
            hotkeyRegistered
                ? "  • Click the chevron or press ⌥⌘B to hide/show items."
                : "  • Click the chevron to hide/show items. (⌥⌘B is unavailable — another app claimed it.)",
            "  • ⌘-drag icons to the LEFT of ╱ to let Pelmet manage them.",
        ]
        if Preferences.autoRehide {
            lines.append("  • Revealed items re-hide after \(Int(Preferences.rehideDelay)) s (right-click the chevron → Settings).")
        }
        lines.append(contentsOf: [
            "  • Nothing visible? A full menu bar or the notch hides items that don't fit —",
            "    quit another menu bar app to free space, then relaunch Pelmet.",
            "  • Ctrl-C here (or closing this terminal) quits Pelmet.",
        ])
        print(lines.joined(separator: "\n"))
        // stdout is block-buffered when redirected (pipe/file); flush so the
        // banner isn't held back until the app exits.
        fflush(stdout)
    }
}
