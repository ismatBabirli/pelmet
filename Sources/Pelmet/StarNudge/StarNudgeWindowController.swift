import AppKit
import PelmetCore
import SwiftUI

/// Owns Pelmet's single, reusable "star us on GitHub" nudge window and the gate
/// that keeps it timed, rate-limited, and never stacked on another surface.
final class StarNudgeWindowController: NSWindowController, NSWindowDelegate {

    static let shared = StarNudgeWindowController()

    private var isTrackedAsOpen = false
    private var hasCenteredWindow = false

    private convenience init() {
        self.init(window: nil)
    }

    /// True when the QA override is set: shows the nudge immediately, bypassing
    /// the time/usage gate, and without advancing the counters or the cap.
    private var isForced: Bool {
        ProcessInfo.processInfo.environment["PELMET_FORCE_STAR_NUDGE"] != nil
    }

    /// The single entry point. Presents the nudge only when the policy allows it
    /// (or the QA override is set) and no other launch surface is up. Safe to
    /// call on every onboarding pass; it self-gates.
    func maybePresent() {
        guard window?.isVisible != true else { return }

        if !isForced {
            guard StarNudgePolicy.shouldShow(
                firstLaunchAt: Preferences.firstLaunchAt,
                hasManagedItems: Preferences.hasEverManagedItems,
                dismissedPermanently: Preferences.starNudgeDismissed,
                lastShownAt: Preferences.starNudgeLastShownAt,
                showCount: Preferences.starNudgeShowCount,
                now: Date()
            ) else { return }
        }

        // Never cover release notes, a crash alert, or an onboarding tip.
        guard !WhatsNewWindowController.shared.isPendingOrVisible,
              NSApp.modalWindow == nil,
              OnboardingController.shared.activeTipWindow == nil
        else { return }

        show()
    }

    private func show() {
        configureWindowIfNeeded()
        guard let window else { return }

        let hosting = NSHostingController(rootView: StarNudgeView(
            onStar: { [weak self] in self?.handleStar() },
            onLater: { [weak self] in self?.window?.performClose(nil) },
            onDontAsk: { [weak self] in self?.handleDontAsk() }
        ))
        window.contentViewController = hosting
        window.setContentSize(hosting.view.fittingSize)

        // An accessory app must activate explicitly or the window won't come
        // forward; the pattern matches Settings and What's New.
        NSApp.activate(ignoringOtherApps: true)
        if !hasCenteredWindow {
            window.center()
            hasCenteredWindow = true
        }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)

        guard window.isVisible else { return }
        if !isTrackedAsOpen {
            isTrackedAsOpen = true
            UIActivityTracker.shared.surfaceOpened()
        }
        // The QA override never burns a real ask.
        if !isForced { recordShow() }
    }

    /// Advances the rate-limit state once the nudge is actually on screen, then
    /// retires it for good if this was the last allowed ask.
    private func recordShow() {
        Preferences.starNudgeLastShownAt = Date()
        Preferences.starNudgeShowCount += 1
        if Preferences.starNudgeShowCount >= StarNudgePolicy.maxShows {
            Preferences.starNudgeDismissed = true
        }
    }

    private func handleStar() {
        NSWorkspace.shared.open(AppLinks.repo)
        Preferences.starNudgeDismissed = true
        window?.performClose(nil)
    }

    private func handleDontAsk() {
        Preferences.starNudgeDismissed = true
        window?.performClose(nil)
    }

    private func configureWindowIfNeeded() {
        guard window == nil else { return }
        let window = StarNudgeWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Enjoying Pelmet?"
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.delegate = self
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        if isTrackedAsOpen {
            isTrackedAsOpen = false
            UIActivityTracker.shared.surfaceClosed()
        }
        // Let any surface queued behind this one get its turn.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            MenuBarManager.shared.reapplyOnboardingChecks()
        }
    }
}

/// Escape closes the nudge (treated as "maybe later") without needing a hidden
/// SwiftUI button just to own the cancel shortcut.
private final class StarNudgeWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }
}
