import SwiftUI

/// One-Click Access pane: the opt-in Accessibility tier. Kept as its own
/// pane because it is the app's entire permission story — the
/// zero-permission core is sacred (see CONTRIBUTING ground rules).
struct OneClickAccessPaneView: View {

    @AppStorage(Preferences.Keys.activationEngineEnabled) private var activationEngineEnabled = false
    @ObservedObject private var activation = ActivationStatus.shared

    var body: some View {
        Form {
            Section {
                // setEnabled persists the preference; @AppStorage picks the
                // change up from UserDefaults. Don't write the key directly.
                Toggle("Open hidden icons with one click", isOn: Binding(
                    get: { activationEngineEnabled },
                    set: { enabled in
                        MenuBarManager.shared.shelfEngine.setEnabled(enabled)
                        if enabled { MenuBarManager.shared.shelfEngine.requestAccess() }
                    }
                ))
            } footer: {
                Text("Pelmet will read which app owns each menu bar icon and simulate "
                    + "clicks to open them. It never reads your screen. Turn this off any "
                    + "time; everything else keeps working.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if activationEngineEnabled {
                Section {
                    switch activation.availability {
                    case .granted:
                        LabeledContent("Accessibility permission", value: "Granted")
                    case .denied:
                        VStack(alignment: .leading, spacing: 4) {
                            LabeledContent("Accessibility permission", value: "Not granted")
                            Text("Grant it in System Settings → Privacy & Security → Accessibility.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Open System Settings…") {
                                openAccessibilitySettings()
                            }
                        }
                    case .notDetermined:
                        LabeledContent("Accessibility permission", value: "Waiting for approval…")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func openAccessibilitySettings() {
        AXPermissionMonitor.openSystemSettings()
    }
}
