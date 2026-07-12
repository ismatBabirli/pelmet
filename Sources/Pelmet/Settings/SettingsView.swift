import AppKit
import SwiftUI
import ServiceManagement

struct SettingsView: View {

    @AppStorage(Preferences.Keys.autoRehide) private var autoRehide = true
    @AppStorage(Preferences.Keys.rehideDelay) private var rehideDelay = 10.0
    @AppStorage(Preferences.Keys.showSwallowedCount) private var showSwallowedCount = true
    @AppStorage(Preferences.Keys.shelfEnabled) private var shelfEnabled = true
    @AppStorage(Preferences.Keys.activationEngineEnabled) private var activationEngineEnabled = false
    @ObservedObject private var status = LayoutStatus.shared
    @ObservedObject private var activation = ActivationStatus.shared
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)
    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            Section {
                Label {
                    Text("Pelmet hides everything to the **left** of the ╱ divider. ⌘-drag icons you want always visible to its **right**, next to the clock.")
                } icon: {
                    Image(systemName: "hand.draw")
                        .foregroundStyle(.tint)
                }
                .font(.callout)
            }

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
            }

            if status.hasNotchedDisplay {
                Section("Menu Bar Space") {
                    LabeledContent(
                        "Icons that don't fit",
                        value: status.swallowedCount == 0 ? "None right now" : "\(status.swallowedCount)"
                    )
                    Toggle("Show a count on the chevron when icons don't fit", isOn: $showSwallowedCount)

                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Open the Shelf when clicking the count", isOn: $shelfEnabled)
                        Text("The Shelf is a panel under the notch listing the icons macOS hid. "
                            + "Turned off, a click always hides/shows icons instead — the Shelf stays "
                            + "one right-click (or ⌥⌘N) away.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    LabeledContent("Icon spacing", value: status.spacingProfile.label)
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

                Section("One-Click Access") {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Open hidden icons with one click", isOn: Binding(
                            get: { activationEngineEnabled },
                            set: { enabled in
                                MenuBarManager.shared.shelfEngine.setEnabled(enabled)
                                if enabled { MenuBarManager.shared.shelfEngine.requestAccess() }
                            }
                        ))
                        Text("Pelmet will read which app owns each menu bar icon and simulate "
                            + "clicks to open them. It never reads your screen. Turn this off any "
                            + "time; everything else keeps working.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if activationEngineEnabled {
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
            } else {
                Section("Menu Bar Space") {
                    Label {
                        Text("This Mac has no camera notch — icons rarely run out of room.")
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }

            Section("General") {
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

                LabeledContent("Toggle shortcut", value: "⌥⌘B")
                LabeledContent("Shelf shortcut", value: "⌥⌘N")

                Button("Show Welcome Tips Again") {
                    OnboardingController.shared.replayTips()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
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
