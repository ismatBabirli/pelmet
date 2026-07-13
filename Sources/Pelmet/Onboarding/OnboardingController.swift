import AppKit
import PelmetCore
import SwiftUI

/// One-time teaching popovers. Popovers (not menus) because they point at
/// physical locations in the menu bar; each shows exactly once, tracked by
/// a Preferences flag, and they chain divider → toggle so the user is never
/// shown two at once. Esc or a click elsewhere dismisses (`.semitransient`).
final class OnboardingController: NSObject, NSPopoverDelegate {

    static let shared = OnboardingController()

    private var activePopover: NSPopover?
    private weak var anchorButton: NSStatusBarButton?
    private var tipMoveObserver: NSObjectProtocol?
    private var tipCorrectionCount = 0
    /// Hitting this cap means AppKit keeps re-applying a bad frame — stop
    /// rather than ping-pong. macOS 26 was observed to re-fight twice before
    /// settling (3 corrections total), so leave real headroom.
    private static let maxTipCorrections = 8

    // MARK: - Entry points (called on confirmed layout snapshots)

    /// First-launch teaching. The welcome anchors on the TOGGLE — always
    /// present and auto-rescued — so a divider born behind the notch can no
    /// longer stall onboarding. The divider spotlight is a second, opportunistic
    /// tip that waits for the ╱ to actually surface and blocks nothing.
    func maybeShowLaunchTips(
        separator: NSStatusItem, toggle: NSStatusItem,
        separatorVisible: Bool, toggleVisible: Bool
    ) {
        guard activePopover == nil else { return }

        // 1. Welcome (on the toggle): teaches the ╱ concept AND click-to-hide.
        if !Preferences.didShowToggleTip {
            guard toggleVisible, let button = toggle.button else { return }
            let delay = Int(Preferences.rehideDelay)
            if show(
                title: "Welcome to Pelmet",
                message: "This ‹/› chevron hides everything to the left of the ╱ divider. "
                    + "Click it (or press ⌥⌘B) to clear the clutter, click again to bring it back. "
                    + "⌘-drag the icons you always want visible to the divider's right, next to the "
                    + "clock. Revealed icons re-hide after \(delay) seconds; change that in Settings.",
                buttonTitle: "Got It",
                on: button
            ) {
                Preferences.didShowToggleTip = true
            }
            return
        }

        // 2. Divider spotlight (on the separator): opportunistic — only once the
        //    ╱ is genuinely visible; otherwise retried on a later snapshot.
        if !Preferences.didShowDividerTip {
            guard separatorVisible, let button = separator.button else { return }
            if show(
                title: "This is your divider",
                message: "Pelmet hides everything to the left of this ╱. ⌘-drag icons to its "
                    + "right to keep them next to the clock, always visible.",
                buttonTitle: "Got It",
                on: button
            ) {
                Preferences.didShowDividerTip = true
            }
        }
    }

    /// The first time icons are detected hidden by the notch: explain the
    /// count once, quietly. New users learn the Shelf here too — no second
    /// popover for them.
    func maybeShowSwallowedEducation(count: Int, toggle: NSStatusItem) {
        guard activePopover == nil,
              !Preferences.didShowSwallowedEducation,
              Preferences.didShowToggleTip,
              count > 0,
              let button = toggle.button else { return }
        let phrase = count == 1 ? "1 icon doesn't fit" : "\(count) icons don't fit"
        guard show(
            title: phrase,
            message: "The notch hides menu bar icons that run out of room, and macOS gives no warning. "
                + "Pelmet shows a count beside its chevron whenever that happens. "
                + "Click the chevron to open the Shelf and see exactly what's hidden; "
                + "right-click for ways to make room.",
            buttonTitle: "OK",
            on: button
        ) else { return }
        Preferences.didShowSwallowedEducation = true
        Preferences.didShowShelfTip = true
    }

    /// For users who learned the count BEFORE the Shelf existed: one quiet
    /// popover the next time something is actually hidden.
    func maybeShowShelfTip(count: Int, toggle: NSStatusItem) {
        guard activePopover == nil,
              Preferences.didShowSwallowedEducation,
              !Preferences.didShowShelfTip,
              Preferences.shelfEnabled,
              count > 0,
              let button = toggle.button else { return }
        guard show(
            title: "See what's hidden",
            message: "New: when the chevron shows +\(count), click it to open the Shelf, "
                + "a panel listing the icons the notch hid. ⌥⌘N works too.",
            buttonTitle: "Got It",
            on: button
        ) else { return }
        Preferences.didShowShelfTip = true
    }

    /// Offers the opt-in "one-click access" feature once, on notched Macs where
    /// it matters. On the genuine first run it PROACTIVELY fires the system
    /// Accessibility prompt (context popover first, OS dialog a beat later); on
    /// a replay it only shows the pitch and waits for the button. Either way the
    /// engine stays off until the grant lands (see `offerOneClick`).
    func maybeOfferOneClick(toggle: NSStatusItem) {
        guard activePopover == nil,
              !Preferences.didOfferOneClick,
              LayoutStatus.shared.hasNotchedDisplay,
              !Preferences.activationEngineEnabled,
              StatusItemActivationEngine.shared.availability != .granted,
              let button = toggle.button else { return }

        let autoPrompt = !Preferences.didAutoPromptAccessibility

        guard show(
            title: "Open hidden icons with one click",
            message: "Turn on One-Click Access and Pelmet can open the icons the notch hides "
                + "with a single click. It reads which app owns each icon and simulates a click. "
                + "It never reads your screen, and you can turn it off any time in "
                + "Settings → One-Click Access.",
            buttonTitle: autoPrompt ? "Got It" : "Enable One-Click Access…",
            on: button,
            action: autoPrompt ? nil : { StatusItemActivationEngine.shared.offerOneClick(proactive: false) }
        ) else { return }
        Preferences.didOfferOneClick = true

        if autoPrompt {
            Preferences.didAutoPromptAccessibility = true
            // Context first, system dialog second — never a bare OS modal.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                StatusItemActivationEngine.shared.offerOneClick(proactive: true)
            }
        }
    }

    /// Settings → "Show Welcome Tips Again".
    func replayTips() {
        Preferences.resetOnboardingFlags()
        MenuBarManager.shared.reapplyOnboardingChecks()
    }

    /// Closes the active tip. Pass a button to close only a tip anchored to
    /// it — used before a status item is recreated, which destroys the
    /// window the popover is tethered to and would orphan it mid-air.
    /// close() (not performClose): immediate, skips the delegate veto and
    /// the close animation that would race removeStatusItem, and still fires
    /// popoverDidClose, whose chain re-runs the onboarding checks.
    func closeActiveTip(ifAnchoredTo button: NSStatusBarButton? = nil) {
        if let button, anchorButton !== button { return }
        activePopover?.close()
    }

    // MARK: - Popover plumbing

    /// The tip popover's own window, if a tip is showing.
    var activeTipWindow: NSWindow? { activePopover?.contentViewController?.view.window }

    /// The anchor button's rect in screen coordinates, if a tip is showing.
    var activeTipAnchorRect: NSRect? {
        guard let button = anchorButton, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    /// A popover anchored to a window-less, hidden, or zero-sized button
    /// lands nowhere (or throws). Notch-swallowed buttons pass this check —
    /// their window is on-screen, under the notch — so layout-dependent
    /// callers additionally gate on the classifier's toggleVisible.
    /// occlusionState is deliberately not consulted: macOS 26 reports
    /// visible status items as occluded (see NotchLayoutMonitor).
    private func canAnchor(_ button: NSStatusBarButton) -> Bool {
        guard let window = button.window else { return false }
        return window.isVisible && !window.frame.isEmpty
            && window.screen != nil && !button.bounds.isEmpty
    }

    /// Shows a tip anchored under `button`. Returns false — leaving the
    /// caller's once-only flag unburned for a retry on a later confirmed
    /// snapshot — when the button can't anchor a popover or AppKit declines.
    private func show(
        title: String, message: String, buttonTitle: String,
        on button: NSStatusBarButton, action: (() -> Void)? = nil
    ) -> Bool {
        guard canAnchor(button) else { return false }
        let popover = NSPopover()
        popover.behavior = .semitransient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: TipView(title: title, message: message, buttonTitle: buttonTitle) { [weak popover] in
                action?()
                popover?.performClose(nil)
            }
        )
        // Assigned before show(): with animates off, popoverDidShow (and the
        // placement fix-up, which reads these) fires synchronously inside it.
        activePopover = popover
        anchorButton = button
        tipCorrectionCount = 0
        UIActivityTracker.shared.surfaceOpened()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        guard popover.isShown else {
            // AppKit declined silently; unwind so the tip can retry later.
            activePopover = nil
            anchorButton = nil
            UIActivityTracker.shared.surfaceClosed()
            return false
        }
        return true
    }

    func popoverDidShow(_ notification: Notification) {
        correctTipPlacementIfNeeded()
        // The toggle is variable-length: if its window moves or resizes while
        // a tip is open, AppKit re-tracks the anchor — and can re-apply a
        // displaced frame. The tolerance check makes this self-terminating
        // (our own corrective setFrame lands in-tolerance → no-op).
        if tipMoveObserver == nil, let tipWindow = activeTipWindow {
            tipMoveObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification, object: tipWindow, queue: .main
            ) { [weak self] _ in
                self?.correctTipPlacementIfNeeded()
            }
        }
    }

    /// macOS 26 can place a status-item popover one popover-height below its
    /// anchor (arrow up, pointing at the desktop; X correct). The cause is
    /// OS-internal, so detect the symptom against the anchor's real screen
    /// rect and translate the window back — a pure vertical move keeps the
    /// arrow aligned.
    private func correctTipPlacementIfNeeded() {
        guard tipCorrectionCount < Self.maxTipCorrections,
              let popover = activePopover, popover.isShown,
              let tipWindow = activeTipWindow,
              let anchorRect = activeTipAnchorRect,
              let screen = anchorButton?.window?.screen else { return }
        guard let corrected = TipPlacement.correctedFrame(
            popoverFrame: tipWindow.frame,
            anchorRect: anchorRect,
            screenFrame: screen.frame
        ) else { return }
        tipCorrectionCount += 1
        print("Pelmet: corrected a detached tip popover (deltaY=\(Int(tipWindow.frame.maxY - anchorRect.minY))).")
        tipWindow.setFrame(corrected, display: true)
    }

    func popoverDidClose(_ notification: Notification) {
        if let tipMoveObserver { NotificationCenter.default.removeObserver(tipMoveObserver) }
        tipMoveObserver = nil
        anchorButton = nil
        tipCorrectionCount = 0
        activePopover = nil
        UIActivityTracker.shared.surfaceClosed()
        // Chain to the next pending tip (divider tip → toggle tip → count
        // education) once the layout facts are re-confirmed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            MenuBarManager.shared.reapplyOnboardingChecks()
        }
    }
}

private struct TipView: View {
    let title: String
    let message: String
    let buttonTitle: String
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(buttonTitle, action: dismiss)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}
