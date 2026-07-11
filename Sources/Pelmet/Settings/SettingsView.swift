import SwiftUI
import ServiceManagement

struct SettingsView: View {

    @AppStorage(Preferences.Keys.autoRehide) private var autoRehide = true
    @AppStorage(Preferences.Keys.rehideDelay) private var rehideDelay = 10.0
    @AppStorage(Preferences.Keys.showSwallowedCount) private var showSwallowedCount = true
    @ObservedObject private var status = LayoutStatus.shared
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

                Button("Show Welcome Tips Again") {
                    OnboardingController.shared.replayTips()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
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
