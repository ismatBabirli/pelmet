import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    static let shared = SettingsWindowController()

    private convenience init() {
        let hosting = NSHostingController(rootView: SettingsRootView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Pelmet Settings"   // still read by Mission Control and accessibility
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        // System Settings look: the sidebar material runs to the top edge and
        // the selected pane names the window from inside the detail column.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
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
