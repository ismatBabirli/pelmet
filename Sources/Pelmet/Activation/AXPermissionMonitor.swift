import AppKit
import ApplicationServices

/// Tracks the Accessibility grant reactively. There is no TCC KVO, so:
/// recompute on app-activation round-trips (the return from System
/// Settings), and poll briefly right after the prompt was triggered —
/// that's the window where the user is actively flipping the switch.
final class AXPermissionMonitor {

    static let shared = AXPermissionMonitor()

    /// Fired (on main) whenever the trusted state may have changed.
    var onChange: (() -> Void)?

    private var observers: [NSObjectProtocol] = []
    private var pollTimer: Timer?
    private var pollDeadline = Date.distantPast
    private var lastKnownTrusted = AXIsProcessTrusted()

    private static let pollInterval: TimeInterval = 2
    private static let pollWindow: TimeInterval = 120

    func startObserving() {
        guard observers.isEmpty else { return }
        let recompute: (Notification) -> Void = { [weak self] _ in self?.recompute() }
        observers = [
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil, queue: .main, using: recompute
            ),
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil, queue: .main, using: recompute
            ),
        ]
    }

    /// Triggers the system prompt (once per install unless the user resets
    /// TCC) and arms the polling window that catches the grant.
    func requestWithPrompt() {
        Preferences.didPromptForAccessibility = true
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true,
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        armPolling()
        recompute()
    }

    /// Deep-links to the Accessibility pane. The single home for this URL —
    /// needed because `AXIsProcessTrustedWithOptions` will not re-show the OS
    /// modal once the app is already listed (even if toggled off), so every
    /// opt-in surface must be able to fall back to System Settings.
    static func openSystemSettings() {
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    func recompute() {
        let trusted = AXIsProcessTrusted()
        guard trusted != lastKnownTrusted else { return }
        lastKnownTrusted = trusted
        if trusted { disarmPolling() }
        onChange?()
    }

    private func armPolling() {
        pollDeadline = Date().addingTimeInterval(Self.pollWindow)
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(
            withTimeInterval: Self.pollInterval, repeats: true
        ) { [weak self] _ in
            guard let self else { return }
            if Date() > self.pollDeadline || self.lastKnownTrusted {
                self.disarmPolling()
                return
            }
            self.recompute()
        }
    }

    private func disarmPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
