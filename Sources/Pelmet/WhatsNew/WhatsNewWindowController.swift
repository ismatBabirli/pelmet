import AppKit
import PelmetCore
import SwiftUI

/// Owns Pelmet's single, reusable release-notes window and the launch gate that
/// keeps it from stacking with onboarding or crash prompts.
final class WhatsNewWindowController: NSWindowController, NSWindowDelegate {

    static let shared = WhatsNewWindowController()

    private struct Presentation {
        let versionLabel: String
        let releases: [ChangelogRelease]
        let versionToAcknowledge: String?
    }

    private var pendingPresentation: Presentation?
    private var acknowledgmentSession: WhatsNewAcknowledgmentSession?
    private var afterPresentationActions: [() -> Void] = []
    private var retryScheduled = false
    private var isTrackedAsOpen = false
    private var hasCenteredWindow = false

    /// True while automatic notes are waiting for another modal to finish or
    /// while this window is visible. Launch-time presenters use it as a gate.
    var isPendingOrVisible: Bool {
        pendingPresentation != nil || window?.isVisible == true
    }

    private convenience init() {
        self.init(window: nil)
    }

    /// Called before menu setup writes any defaults. A new install silently
    /// records a baseline; an existing install receives the current notes once.
    func prepareAutomaticPresentation(hadExistingPreferences: Bool) {
        let releases = Self.loadBundledReleases()
        switch WhatsNewPolicy.decision(
            currentVersion: AppVersionInfo.current.shortVersion,
            lastAcknowledgedVersion: Preferences.lastAcknowledgedWhatsNewVersion,
            hadExistingPreferences: hadExistingPreferences,
            releases: releases
        ) {
        case .none:
            break
        case let .establishBaseline(version):
            Preferences.lastAcknowledgedWhatsNewVersion = version.description
        case let .present(content):
            pendingPresentation = Presentation(
                versionLabel: content.currentVersion.description,
                releases: content.releases,
                versionToAcknowledge: content.currentVersion.description
            )
        }
    }

    /// Presents prepared automatic notes once AppDelegate has finished wiring
    /// the app. If Sparkle owns a modal at that moment, retry without stacking.
    func presentPreparedIfNeeded() {
        guard pendingPresentation != nil else { return }
        guard NSApp.modalWindow == nil else {
            schedulePresentationRetry()
            return
        }
        presentPending()
    }

    /// Permanent replay path from Settings > About. If automatic notes are
    /// pending, replaying them counts as the same presentation and acknowledges
    /// them only when this window closes.
    func showManually() {
        if window?.isVisible == true {
            bringWindowForward()
            return
        }

        OnboardingController.shared.closeActiveTip()
        if pendingPresentation != nil {
            presentPending()
            return
        }

        let version = AppVersionInfo.current
        let releases = Self.loadBundledReleases()
        let currentRelease = version.shortVersion
            .flatMap(SemanticVersion.init)
            .flatMap { current in releases.first { $0.version == current } }
        show(Presentation(
            versionLabel: version.shortVersion ?? version.displayValue,
            releases: currentRelease.map { [$0] } ?? [],
            versionToAcknowledge: nil
        ))
    }

    /// Queues launch UI that must not cover this window. The action runs on the
    /// next main-loop turn after dismissal so AppKit can finish closing first.
    func performAfterPresentation(_ action: @escaping () -> Void) {
        guard isPendingOrVisible else {
            action()
            return
        }
        afterPresentationActions.append(action)
    }

    private func presentPending() {
        guard let pendingPresentation else { return }
        guard NSApp.modalWindow == nil else {
            schedulePresentationRetry()
            return
        }
        show(pendingPresentation)
    }

    private func show(_ presentation: Presentation) {
        configureWindowIfNeeded()
        guard let window else { return }

        window.title = "What's New in Pelmet \(presentation.versionLabel)"
        window.contentViewController = NSHostingController(rootView: WhatsNewView(
            versionLabel: presentation.versionLabel,
            releases: presentation.releases,
            onDone: { [weak self] in self?.window?.performClose(nil) }
        ))

        NSApp.activate(ignoringOtherApps: true)
        if !hasCenteredWindow {
            window.center()
            hasCenteredWindow = true
        }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)

        guard window.isVisible else { return }
        pendingPresentation = nil
        if let rawVersion = presentation.versionToAcknowledge,
           let version = SemanticVersion(rawVersion) {
            acknowledgmentSession = WhatsNewAcknowledgmentSession(version: version)
            acknowledgmentSession?.recordSuccessfulOpen()
        }
        if !isTrackedAsOpen {
            isTrackedAsOpen = true
            UIActivityTracker.shared.surfaceOpened()
        }
    }

    private func configureWindowIfNeeded() {
        guard window == nil else { return }
        let window = WhatsNewWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "What's New in Pelmet"
        window.minSize = NSSize(width: 460, height: 360)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.delegate = self
        self.window = window
    }

    private func bringWindowForward() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func schedulePresentationRetry() {
        guard !retryScheduled else { return }
        retryScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            self.retryScheduled = false
            self.presentPreparedIfNeeded()
        }
    }

    func windowWillClose(_ notification: Notification) {
        if var session = acknowledgmentSession,
           let version = session.recordDismissal() {
            Preferences.lastAcknowledgedWhatsNewVersion = version.description
        }
        acknowledgmentSession = nil
        if isTrackedAsOpen {
            isTrackedAsOpen = false
            UIActivityTracker.shared.surfaceClosed()
        }

        let actions = afterPresentationActions
        afterPresentationActions.removeAll()
        DispatchQueue.main.async {
            actions.forEach { $0() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                MenuBarManager.shared.reapplyOnboardingChecks()
            }
        }
    }

    private static func loadBundledReleases() -> [ChangelogRelease] {
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
              let markdown = try? String(contentsOf: url, encoding: .utf8)
        else { return [] }
        return ChangelogParser.parse(markdown)
    }
}

/// Escape closes the focused release-notes window without requiring a hidden
/// SwiftUI button solely to own the cancel keyboard shortcut.
private final class WhatsNewWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }
}
