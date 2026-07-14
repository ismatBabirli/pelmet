import PelmetCore
import ServiceManagement
import SwiftUI

/// General pane: the core mental model, re-hide behavior, startup and
/// shortcuts. This is the landing pane — Settings doubles as the escape
/// hatch when the user can't find the chevron (see AppDelegate reopen).
struct GeneralPaneView: View {

    @AppStorage(Preferences.Keys.autoRehide) private var autoRehide = true
    @AppStorage(Preferences.Keys.rehideDelay) private var rehideDelay = 10.0
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)
    @State private var launchAtLoginError: String?
    @State private var autoCheckUpdates = UpdaterController.shared.automaticallyChecksForUpdates
    @State private var telemetryEnabled = Preferences.telemetryEnabled
    @State private var didResetInstallID = false
    /// When set in the environment, DO_NOT_TRACK wins over the toggle.
    private let doNotTrack = TelemetryGate.envFlagSet(
        ProcessInfo.processInfo.environment["DO_NOT_TRACK"]
    )

    var body: some View {
        Form {
            Section("Behavior") {
                Toggle("Automatically re-hide items", isOn: $autoRehide)

                if autoRehide {
                    VStack(alignment: .leading) {
                        Slider(value: $rehideDelay, in: 3...60, step: 1) {
                            Text("Re-hide after")
                        }
                        Text("\(Int(rehideDelay)) seconds")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Binding with a setter side effect instead of .onChange —
                // the non-deprecated onChange(of:initial:_:) needs macOS 14.
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { enabled in
                        launchAtLogin = enabled
                        updateLaunchAtLogin(enabled)
                    }
                ))

                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Shortcuts") {
                LabeledContent("Toggle shortcut", value: "⌥⌘B")
                LabeledContent("Shelf shortcut", value: "⌥⌘N")
            }

            // Sparkle owns the "check automatically" preference (its own
            // defaults, no Preferences key). Hidden under `swift run`, where
            // Sparkle is absent and the updater can't run without a bundle.
            if UpdaterController.shared.isAvailable {
                Section("Software Update") {
                    Toggle("Automatically check for updates", isOn: Binding(
                        get: { autoCheckUpdates },
                        set: { enabled in
                            autoCheckUpdates = enabled
                            UpdaterController.shared.automaticallyChecksForUpdates = enabled
                        }
                    ))
                    Button("Check for Updates…") {
                        UpdaterController.shared.checkForUpdates(nil)
                    }
                }
            }

            // Always shown (honest even under `swift run`, where the send gate
            // keeps it inert). The toggle routes through TelemetryManager so
            // opting out also forgets the install ID.
            Section {
                Toggle("Share anonymous usage statistics", isOn: Binding(
                    get: { telemetryEnabled && !doNotTrack },
                    set: { enabled in
                        telemetryEnabled = enabled
                        TelemetryManager.shared.setEnabled(enabled)
                    }
                ))
                .disabled(doNotTrack)

                DisclosureGroup("What exactly is sent?") {
                    // Rendered from the same builder used on the wire, so the
                    // preview cannot drift from reality.
                    Text(TelemetryManager.shared.currentPreviewJSON())
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Link("Full documentation", destination: AppLinks.telemetryDoc)
                    Button(didResetInstallID ? "Install ID reset" : "Reset Install ID") {
                        TelemetryManager.shared.resetInstallID()
                        didResetInstallID = true
                    }
                    .disabled(didResetInstallID)
                }
            } header: {
                Text("Privacy")
            } footer: {
                Text(doNotTrack
                    ? "Disabled by the DO_NOT_TRACK environment variable."
                    : "One anonymous ping per day: app version, macOS version, chip type, and "
                        + "which Pelmet features are on. Never your menu bar contents or other "
                        + "apps' names. IP addresses are discarded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Button("Show Welcome Tips Again") {
                    OnboardingController.shared.replayTips()
                }
            } footer: {
                // Settings doubles as the "can't find the chevron" escape
                // hatch (AppDelegate reopen), so the core mental model stays
                // stated here, compactly.
                Label {
                    Text("Pelmet hides everything to the **left** of the ╱ divider. ⌘-drag icons you want always visible to its **right**, next to the clock.")
                } icon: {
                    Image(systemName: "hand.draw")
                        .foregroundStyle(.tint)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            // SMAppService only works from a real .app bundle —
            // it will throw when running via `swift run`.
            launchAtLoginError = "Launch at login requires running as a bundled .app (build with Xcode)."
            launchAtLogin = false
        }
    }
}
