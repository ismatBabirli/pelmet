import SwiftUI

/// Menu Bar Space pane: what the notch is hiding right now, the chevron
/// count, the Shelf, and icon-spacing remedies. On Macs without a notch it
/// collapses to an informational note.
struct MenuBarSpacePaneView: View {

    @AppStorage(Preferences.Keys.showSwallowedCount) private var showSwallowedCount = true
    @AppStorage(Preferences.Keys.shelfEnabled) private var shelfEnabled = true
    @ObservedObject private var status = LayoutStatus.shared

    var body: some View {
        Form {
            if status.hasNotchedDisplay {
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
                    Text("The Shelf is a panel under the notch listing the icons macOS hid. "
                        + "Turned off, a click always hides/shows icons instead; the Shelf stays "
                        + "one right-click (or ⌥⌘N) away.")
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
                        Text("This Mac has no camera notch, so icons rarely run out of room.")
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
