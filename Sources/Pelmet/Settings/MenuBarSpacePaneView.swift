import SwiftUI

/// Menu Bar Space pane: what a notch or software island is hiding, the chevron
/// count, the Shelf, and icon-spacing remedies. On Macs without a notch it
/// collapses to an informational note.
struct MenuBarSpacePaneView: View {

    @AppStorage(Preferences.Keys.showSwallowedCount) private var showSwallowedCount = true
    @AppStorage(Preferences.Keys.shelfEnabled) private var shelfEnabled = true
    @ObservedObject private var status = LayoutStatus.shared
    @ObservedObject private var softwareIslands = SoftwareIslandMonitor.shared
    @ObservedObject private var hotkeys = HotkeyStatus.shared

    /// " (or ⌥⌘N)", or nothing when the user cleared the Shelf shortcut.
    private var shelfShortcutHint: String {
        hotkeys.bindings.shelf.map { " (or \(HotkeyDisplay.string(for: $0)))" } ?? ""
    }

    var body: some View {
        Form {
            Section {
                if softwareIslands.candidates.isEmpty {
                    Text("No software island app is running. Vibe Island is supported automatically; other top-center overlay apps appear here for local calibration.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(softwareIslands.candidates) { candidate in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.displayName)
                                    Text(candidate.isKnown ? "Known app" : "Detected locally")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Toggle("Include in coverage detection", isOn: Binding(
                                    get: { candidate.enabled },
                                    set: { softwareIslands.setEnabled($0, for: candidate) }
                                ))
                                .labelsHidden()
                            }
                            if candidate.enabled {
                                HStack {
                                    Text("Island width")
                                    Slider(value: Binding(
                                        get: { candidate.restingWidth },
                                        set: { softwareIslands.setRestingWidth($0, for: candidate) }
                                    ), in: 80...800, step: 2)
                                    Text("\(Int(candidate.restingWidth)) pt")
                                        .monospacedDigit()
                                        .frame(width: 52, alignment: .trailing)
                                }
                                .font(.caption)
                            }
                        }
                    }
                }
            } header: {
                Text("Software Islands")
            } footer: {
                Text("Detection uses window position and app metadata without Screen Recording or Accessibility access. Width changes update the covered-icon count and Shelf live. Pelmet cannot move other apps' menu items around a centered overlay. Hover expansion is ignored, and unknown apps are never enabled automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if status.hasMenuBarObstruction {
                Section {
                    LabeledContent(
                        "Icons that don't fit",
                        value: status.swallowedCount == 0 ? "None right now" : "\(status.swallowedCount)"
                    )
                    Toggle("Show a count on the chevron when icons don't fit", isOn: $showSwallowedCount)
                }

                Section {
                    Toggle("Open the Shelf when clicking the count", isOn: $shelfEnabled)
                } footer: {
                    Text("The Shelf is a panel below the obstruction listing covered icons. "
                        + "Turned off, a click always hides/shows icons instead; the Shelf stays "
                        + "one right-click\(shelfShortcutHint) away.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section("Icon Spacing") {
                    LabeledContent("Current spacing", value: status.spacingProfile.label)
                    HStack {
                        Button("Make Room…") {
                            MakeRoomWindowController.shared.show()
                        }
                        if status.spacingProfile != .systemDefault {
                            Button("Restore Default Spacing…") {
                                MenuBarSpacing.apply(.systemDefault)
                                status.refreshSpacing()
                            }
                        }
                    }
                }
            } else {
                Section {
                    Label {
                        Text("No physical notch or enabled software island is currently taking menu bar space.")
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            softwareIslands.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .pelmetSoftwareIslandConfigurationDidChange
        )) { _ in
            status.refresh(
                swallowedCount: status.swallowedCount,
                shelfEntries: status.shelfEntries
            )
        }
    }
}
