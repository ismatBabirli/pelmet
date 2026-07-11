import AppKit
import SwiftUI

/// The remedies hub: everything a user can actually do about a menu bar
/// that doesn't fit beside the notch. Non-modal, reachable from the
/// right-click menu, the count education popover's advice, and Settings.
final class MakeRoomWindowController: NSWindowController, NSWindowDelegate {

    static let shared = MakeRoomWindowController()

    private convenience init() {
        let hosting = NSHostingController(rootView: MakeRoomView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Make Room in the Menu Bar"
        window.styleMask = [.titled, .closable]
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

struct MakeRoomView: View {

    @ObservedObject private var status = LayoutStatus.shared
    @State private var showSpacingSheet = false
    @State private var selectedProfile: MenuBarSpacing.Profile = .reduced
    @State private var spacingAppliedNote = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if status.swallowedCount > 0 {
                Label(
                    status.swallowedCount == 1
                        ? "1 icon doesn't fit beside the notch right now."
                        : "\(status.swallowedCount) icons don't fit beside the notch right now.",
                    systemImage: "info.circle"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            remedy(
                symbol: "hand.draw",
                title: "Hide icons with Pelmet",
                text: "Hold ⌘ and drag icons you rarely use to the left of the ╱ divider, then "
                    + "collapse with the ‹ chevron. Keep the essentials on its right."
            )

            remedy(
                symbol: "arrow.left.and.right",
                title: "Tighten icon spacing",
                text: "macOS spaces menu bar icons generously. Reducing the spacing fits more icons "
                    + "beside the notch. No permissions involved — the change takes effect the next "
                    + "time you log in."
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Button("Tighten Spacing…") { showSpacingSheet = true }
                        if status.spacingProfile != .systemDefault {
                            Button("Restore Default…") {
                                MenuBarSpacing.apply(.systemDefault)
                                status.refreshSpacing()
                                spacingAppliedNote = true
                            }
                        }
                    }
                    Text("Current: \(status.spacingProfile.label)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if spacingAppliedNote {
                        Label("Done. The new spacing appears after you log out and back in.",
                              systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            remedy(
                symbol: "switch.2",
                title: "Move system icons into Control Center",
                text: "Wi-Fi, Battery and other system icons can live inside Control Center instead "
                    + "of the menu bar."
            ) {
                Button("Open Control Center Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }

            remedy(
                symbol: "xmark.circle",
                title: "Quit menu bar apps you don't use",
                text: "Every icon costs width. Quitting unused menu bar apps frees space instantly."
            )
        }
        .padding(20)
        .frame(width: 440)
        .sheet(isPresented: $showSpacingSheet) {
            SpacingSheet(selected: $selectedProfile) { applied in
                showSpacingSheet = false
                if applied {
                    MenuBarSpacing.apply(selectedProfile)
                    status.refreshSpacing()
                    spacingAppliedNote = true
                }
            }
        }
    }

    @ViewBuilder
    private func remedy(
        symbol: String,
        title: String,
        text: String,
        @ViewBuilder accessory: () -> some View = { EmptyView() }
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                accessory()
            }
        }
    }
}

private struct SpacingSheet: View {
    @Binding var selected: MenuBarSpacing.Profile
    let completion: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tighten menu bar icon spacing?")
                .font(.headline)
            Text("Pelmet will change the system setting that controls the gap between menu bar "
                + "icons. The new spacing takes effect the next time you log in ( menu ▸ Log Out). "
                + "You can restore the default at any time.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker("Spacing", selection: $selected) {
                Text(MenuBarSpacing.Profile.reduced.label).tag(MenuBarSpacing.Profile.reduced)
                Text(MenuBarSpacing.Profile.compact.label).tag(MenuBarSpacing.Profile.compact)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            HStack {
                Spacer()
                Button("Cancel") { completion(false) }
                    .keyboardShortcut(.cancelAction)
                Button("Tighten Spacing") { completion(true) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}
