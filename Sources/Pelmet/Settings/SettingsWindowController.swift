import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    static let shared = SettingsWindowController()

    private convenience init() {
        let hosting = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Pelmet Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(hosting.view.fittingSize)
        self.init(window: window)
        window.delegate = self
    }

    func show() {
        // Accessory apps need explicit activation to bring windows forward.
        NSApp.activate(ignoringOtherApps: true)
        if window?.isVisible != true {
            window?.center()
            UIActivityTracker.shared.surfaceOpened()
        }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        UIActivityTracker.shared.surfaceClosed()
    }
}
