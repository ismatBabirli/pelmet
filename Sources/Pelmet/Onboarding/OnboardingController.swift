import AppKit
import SwiftUI

/// One-time teaching popovers. Popovers (not menus) because they point at
/// physical locations in the menu bar; each shows exactly once, tracked by
/// a Preferences flag, and they chain divider → toggle so the user is never
/// shown two at once. Esc or a click elsewhere dismisses (`.semitransient`).
final class OnboardingController: NSObject, NSPopoverDelegate {

    static let shared = OnboardingController()

    private var activePopover: NSPopover?

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
            Preferences.didShowToggleTip = true
            let delay = Int(Preferences.rehideDelay)
            show(
                title: "Welcome to Pelmet",
                message: "This ‹/› chevron hides everything to the left of the ╱ divider. "
                    + "Click it (or press ⌥⌘B) to clear the clutter, click again to bring it back. "
                    + "⌘-drag the icons you always want visible to the divider's right, next to the "
                    + "clock. Revealed icons re-hide after \(delay) seconds; change that in Settings.",
                buttonTitle: "Got It",
                on: button
            )
            return
        }

        // 2. Divider spotlight (on the separator): opportunistic — only once the
        //    ╱ is genuinely visible; otherwise retried on a later snapshot.
        if !Preferences.didShowDividerTip {
            guard separatorVisible, let button = separator.button else { return }
            Preferences.didShowDividerTip = true
            show(
                title: "This is your divider",
                message: "Pelmet hides everything to the left of this ╱. ⌘-drag icons to its "
                    + "right to keep them next to the clock, always visible.",
                buttonTitle: "Got It",
                on: button
            )
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
        Preferences.didShowSwallowedEducation = true
        Preferences.didShowShelfTip = true
        let phrase = count == 1 ? "1 icon doesn't fit" : "\(count) icons don't fit"
        show(
            title: phrase,
            message: "The notch hides menu bar icons that run out of room, and macOS gives no warning. "
                + "Pelmet shows a count beside its chevron whenever that happens. "
                + "Click the chevron to open the Shelf and see exactly what's hidden; "
                + "right-click for ways to make room.",
            buttonTitle: "OK",
            on: button
        )
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
        Preferences.didShowShelfTip = true
        show(
            title: "See what's hidden",
            message: "New: when the chevron shows +\(count), click it to open the Shelf, "
                + "a panel listing the icons the notch hid. ⌥⌘N works too.",
            buttonTitle: "Got It",
            on: button
        )
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
        Preferences.didOfferOneClick = true

        let autoPrompt = !Preferences.didAutoPromptAccessibility
        if autoPrompt { Preferences.didAutoPromptAccessibility = true }

        show(
            title: "Open hidden icons with one click",
            message: "Turn on One-Click Access and Pelmet can open the icons the notch hides "
                + "with a single click. It reads which app owns each icon and simulates a click. "
                + "It never reads your screen, and you can turn it off any time in Settings.",
            buttonTitle: autoPrompt ? "Got It" : "Enable One-Click Access…",
            on: button,
            action: autoPrompt ? nil : { StatusItemActivationEngine.shared.offerOneClick(proactive: false) }
        )

        if autoPrompt {
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

    // MARK: - Popover plumbing

    private func show(
        title: String, message: String, buttonTitle: String,
        on button: NSStatusBarButton, action: (() -> Void)? = nil
    ) {
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
        activePopover = popover
        UIActivityTracker.shared.surfaceOpened()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func popoverDidClose(_ notification: Notification) {
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
