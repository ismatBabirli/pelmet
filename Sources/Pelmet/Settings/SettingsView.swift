import SwiftUI
import ServiceManagement

struct SettingsView: View {

    @AppStorage(Preferences.Keys.autoRehide) private var autoRehide = true
    @AppStorage(Preferences.Keys.rehideDelay) private var rehideDelay = 10.0
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)
    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            Section {
                Label {
                    Text("⌘-drag menu bar icons to the **left** of the ╱ divider. Pelmet will hide and reveal everything on that side.")
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

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in
                        updateLaunchAtLogin(enabled)
                    }

                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                LabeledContent("Toggle shortcut", value: "⌥⌘B")
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
