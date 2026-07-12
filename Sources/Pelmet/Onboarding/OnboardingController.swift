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

    /// First-launch teaching, gated on the divider actually being visible —
    /// a divider born behind the notch gets its tip when it first appears.
    func maybeShowLaunchTips(separator: NSStatusItem, toggle: NSStatusItem, separatorVisible: Bool) {
        guard activePopover == nil else { return }

        if !Preferences.didShowDividerTip {
            guard separatorVisible, let button = separator.button else { return }
            Preferences.didShowDividerTip = true
            show(
                title: "Meet your divider",
                message: "When you collapse, Pelmet hides everything to the left of this ╱ divider. "
                    + "Hold ⌘ and drag the icons you always want visible to its right, next to the clock.",
                buttonTitle: "Got It",
                on: button
            )
            return
        }

        if !Preferences.didShowToggleTip {
            guard let button = toggle.button else { return }
            Preferences.didShowToggleTip = true
            let delay = Int(Preferences.rehideDelay)
            show(
                title: "Hide the clutter",
                message: "Click this chevron (or press ⌥⌘B) to hide everything left of ╱ — "
                    + "click again to bring it back. Revealed icons re-hide after \(delay) seconds; "
                    + "change that in Settings.",
                buttonTitle: "Done",
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
              Preferences.didShowDividerTip, Preferences.didShowToggleTip,
              count > 0,
              let button = toggle.button else { return }
        Preferences.didShowSwallowedEducation = true
        Preferences.didShowShelfTip = true
        let phrase = count == 1 ? "1 icon doesn't fit" : "\(count) icons don't fit"
        show(
            title: phrase,
            message: "The notch hides menu bar icons that run out of room — macOS gives no warning. "
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
            message: "New: when the chevron shows +\(count), click it to open the Shelf — "
                + "a panel listing the icons the notch hid. ⌥⌘N works too.",
            buttonTitle: "Got It",
            on: button
        )
    }

    /// Settings → "Show Welcome Tips Again".
    func replayTips() {
        Preferences.resetOnboardingFlags()
        MenuBarManager.shared.reapplyOnboardingChecks()
    }

    // MARK: - Popover plumbing

    private func show(title: String, message: String, buttonTitle: String, on button: NSStatusBarButton) {
        let popover = NSPopover()
        popover.behavior = .semitransient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: TipView(title: title, message: message, buttonTitle: buttonTitle) { [weak popover] in
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
