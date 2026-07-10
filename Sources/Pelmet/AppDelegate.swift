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
        HotkeyManager.shared.register()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
