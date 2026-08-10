import PelmetCore
import ServiceManagement
import SwiftUI

/// General pane: the core mental model, re-hide behavior, startup and
/// shortcuts. This is the landing pane — Settings doubles as the escape
/// hatch when the user can't find the chevron (see AppDelegate reopen).
struct GeneralPaneView: View {

    @ObservedObject private var updater = UpdaterController.shared
    @ObservedObject private var hotkeys = HotkeyStatus.shared
    /// Why the last recording attempt was refused, per action. Cleared as soon as
    /// a combination is accepted or removed.
    @State private var rejections: [HotkeyAction: String] = [:]
    @AppStorage(Preferences.Keys.autoRehide) private var autoRehide = true
    @AppStorage(Preferences.Keys.rehideDelay) private var rehideDelay = 10.0
    @AppStorage(Preferences.Keys.showOnHover) private var showOnHover = false
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
                Toggle("Show hidden items on hover", isOn: $showOnHover)
                Text("Move the pointer into the menu bar to reveal managed items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

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

            Section {
                ForEach(HotkeyAction.allCases, id: \.self) { action in
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent(action.title) {
                            HStack(spacing: 6) {
                                ShortcutRecorder(
                                    action: action,
                                    combo: hotkeys.bindings[action],
                                    onRecord: { record($0, for: action) },
                                    onClear: { clear(action) }
                                )
                                .frame(width: 132, height: 22)

                                if hotkeys.bindings[action] != nil {
                                    Button {
                                        clear(action)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Remove this shortcut")
                                    .accessibilityLabel("Remove the \(action.title) shortcut")
                                }
                            }
                        }

                        if let note = note(for: action) {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Button("Restore Default Shortcuts") {
                    HotkeyManager.shared.restoreDefaults()
                    rejections = [:]
                }
                .disabled(hotkeys.isDefault)
            } header: {
                Text("Shortcuts")
            } footer: {
                Text("Click a shortcut, then press the new keys. A shortcut on a letter or "
                    + "number needs at least two modifiers, like ⌥⌘B, because a single one "
                    + "would override that combination in every app. Esc cancels, ⌫ removes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Sparkle owns the "check automatically" preference (its own
            // defaults, no Preferences key). Hidden under `swift run`, where
            // Sparkle is absent and the updater can't run without a bundle.
            if updater.isAvailable {
                Section("Software Update") {
                    Toggle("Automatically check for updates", isOn: Binding(
                        get: { autoCheckUpdates },
                        set: { enabled in
                            autoCheckUpdates = enabled
                            updater.automaticallyChecksForUpdates = enabled
                        }
                    ))
                    Text(updater.status.settingsText)
                        .font(.caption)
                        .foregroundStyle(updater.status == .failed ? Color.red : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(updater.availableVersion == nil ? "Check for Updates…" : "Review Update…") {
                        updater.checkForUpdates(nil)
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

    /// Routed through the manager, which validates and persists. The pref key is
    /// never written from here.
    private func record(_ combo: KeyCombo, for action: HotkeyAction) -> HotkeyRejection? {
        let rejection = HotkeyManager.shared.setShortcut(combo, for: action)
        rejections[action] = rejection?.message(
            for: combo, keyName: HotkeyDisplay.keyName(for: combo)
        )
        return rejection
    }

    private func clear(_ action: HotkeyAction) {
        HotkeyManager.shared.setShortcut(nil, for: action)
        rejections[action] = nil
    }

    /// A live rejection wins over a registration failure: the user just acted, so
    /// tell them about that before anything older.
    private func note(for action: HotkeyAction) -> String? {
        if let rejection = rejections[action] { return rejection }
        guard hotkeys.outcomes[action] == .unavailable else { return nil }
        let shortcut = hotkeys.bindings[action].map(HotkeyDisplay.string(for:)) ?? "That shortcut"
        return "Another app is already using \(shortcut). Pick a different combination."
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
