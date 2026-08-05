import AppKit
import PelmetCore
import SwiftUI

/// Owns Pelmet's single, reusable support nudge window and its gentle gate.
/// The nudge only follows a completed star ask, so the two requests never
/// appear together or back-to-back for a new user.
final class SupportNudgeWindowController: NSWindowController, NSWindowDelegate {

    static let shared = SupportNudgeWindowController()

    private var isTrackedAsOpen = false
    private var hasCenteredWindow = false

    private convenience init() {
        self.init(window: nil)
    }

    /// True when the QA override is set: shows the nudge immediately, bypassing
    /// timing and usage gates without advancing the counters or cap.
    private var isForced: Bool {
        ProcessInfo.processInfo.environment["PELMET_FORCE_SUPPORT_NUDGE"] != nil
    }

    /// Presents the support nudge when its policy allows it and no other launch
    /// surface is active. Safe to call on every onboarding pass.
    func maybePresent() {
        guard window?.isVisible != true else { return }

        if !isForced {
            guard SupportNudgePolicy.shouldShow(
                firstLaunchAt: Preferences.firstLaunchAt,
                hasManagedItems: Preferences.hasEverManagedItems,
                starNudgeDismissed: Preferences.starNudgeDismissed,
                starNudgeLastShownAt: Preferences.starNudgeLastShownAt,
                dismissedPermanently: Preferences.supportNudgeDismissed,
                lastShownAt: Preferences.supportNudgeLastShownAt,
                showCount: Preferences.supportNudgeShowCount,
                now: Date()
            ) else { return }
        }

        // Never cover the star prompt, release notes, a crash alert, or an
        // onboarding tip. The star window re-runs this check after closing.
        guard !StarNudgeWindowController.shared.isVisible,
              !WhatsNewWindowController.shared.isPendingOrVisible,
              NSApp.modalWindow == nil,
              OnboardingController.shared.activeTipWindow == nil
        else { return }

        show()
    }

    private func show() {
        configureWindowIfNeeded()
        guard let window else { return }

        let hosting = NSHostingController(rootView: SupportNudgeView(
            onSupport: { [weak self] in self?.handleSupport() },
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
        if !isForced { recordShow() }
    }

    private func recordShow() {
        Preferences.supportNudgeLastShownAt = Date()
        Preferences.supportNudgeShowCount += 1
        if Preferences.supportNudgeShowCount >= SupportNudgePolicy.maxShows {
            Preferences.supportNudgeDismissed = true
        }
    }

    private func handleSupport() {
        NSWorkspace.shared.open(AppLinks.support)
        Preferences.supportNudgeDismissed = true
        window?.performClose(nil)
    }

    private func handleDontAsk() {
        Preferences.supportNudgeDismissed = true
        window?.performClose(nil)
    }

    private func configureWindowIfNeeded() {
        guard window == nil else { return }
        let window = SupportNudgeWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Support Pelmet"
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

/// Escape closes the support nudge (treated as "maybe later") without needing
/// a hidden SwiftUI button just to own the cancel shortcut.
private final class SupportNudgeWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }
}
