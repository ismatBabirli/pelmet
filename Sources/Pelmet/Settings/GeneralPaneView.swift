import SwiftUI
import ServiceManagement

/// General pane: the core mental model, re-hide behavior, startup and
/// shortcuts. This is the landing pane — Settings doubles as the escape
/// hatch when the user can't find the chevron (see AppDelegate reopen).
struct GeneralPaneView: View {

    @AppStorage(Preferences.Keys.autoRehide) private var autoRehide = true
    @AppStorage(Preferences.Keys.rehideDelay) private var rehideDelay = 10.0
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)
    @State private var launchAtLoginError: String?

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
