import PelmetCore
import SwiftUI

/// Profile management stays opt-in: opening this pane never moves icons or
/// requests Accessibility. Capture and apply are explicit user actions.
struct ProfilesPaneView: View {

    @ObservedObject private var controller = ProfileController.shared
    @State private var newProfileName = ""
    @State private var editingProfileID: UUID?
    @State private var editingName = ""
    @State private var profileToDelete: MenuBarProfile?

    var body: some View {
        Form {
            Section {
                if controller.profiles.isEmpty {
                    Text("Save your current menu bar arrangement as a profile. "
                        + "Profiles can remember which items stay visible and their order.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(Array(controller.profiles.enumerated()), id: \.element.id) { index, profile in
                        profileRow(profile, index: index)
                    }
                }

                LabeledContent("Profile name") {
                    HStack(alignment: .center, spacing: 10) {
                        TextField("", text: $newProfileName)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 220)
                            .overlay(alignment: .leading) {
                                if newProfileName.isEmpty {
                                    Text("e.g. Work")
                                        .foregroundStyle(.secondary)
                                        .padding(.leading, 6)
                                        .allowsHitTesting(false)
                                }
                            }
                            .onSubmit { saveCurrentProfile() }

                        Button("Create Profile") {
                            saveCurrentProfile()
                        }
                        .disabled(newProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || controller.isBusy)
                    }
                }
            } header: {
                Text("Saved Profiles")
            } footer: {
                Text("Capture records identifiable menu bar items. Items macOS does not expose "
                    + "are left out and reported.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Active Profile") {
                Picker(
                    "Current profile",
                    selection: Binding<String>(
                        get: { controller.activeProfileID?.uuidString ?? "" },
                        set: { controller.setActive(UUID(uuidString: $0)) }
                    )
                ) {
                    Text("None").tag("")
                    ForEach(controller.profiles) { profile in
                        Text(profile.name).tag(profile.id.uuidString)
                    }
                }
                .pickerStyle(.menu)

                Text("The current profile is shown in the chevron menu. Use Apply above to arrange menu bar items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Default Profile") {
                Picker(
                    "Profile used at launch",
                    selection: Binding<String>(
                        get: { controller.defaultProfileID?.uuidString ?? "" },
                        set: { controller.setDefault(UUID(uuidString: $0)) }
                    )
                ) {
                    Text("None").tag("")
                    ForEach(controller.profiles) { profile in
                        Text(profile.name).tag(profile.id.uuidString)
                    }
                }
                .pickerStyle(.menu)

                Toggle(
                    "Apply the default profile at launch",
                    isOn: Binding(
                        get: { controller.applyDefaultAtLaunch },
                        set: { controller.setApplyDefaultAtLaunch($0) }
                    )
                )
                .disabled(controller.defaultProfileID == nil)

                Text("Applying a profile uses Accessibility only when you explicitly "
                    + "save, apply, or opt into launch application. Pelmet never prompts "
                    + "during ordinary startup.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if controller.isBusy {
                Section {
                    ProgressView("Working with the menu bar…")
                }
            }

            if let result = controller.lastResult {
                Section("Last Result") {
                    Text(result.summary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !result.missing.isEmpty {
                        unresolvedList(title: "Not found", placements: result.missing)
                    }
                    if !result.ambiguous.isEmpty {
                        unresolvedList(title: "Ambiguous", placements: result.ambiguous)
                    }
                }
            } else if let lastMessage = controller.lastMessage {
                Section("Last Result") {
                    Text(lastMessage)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .alert(
            "Delete Profile?",
            isPresented: Binding(
                get: { profileToDelete != nil },
                set: { if !$0 { profileToDelete = nil } }
            ),
            presenting: profileToDelete
        ) { profile in
            Button("Delete", role: .destructive) {
                controller.delete(profile.id)
                profileToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                profileToDelete = nil
            }
        } message: { profile in
            Text("Delete \(profile.name)? Its saved arrangement will be removed.")
        }
    }

    private func saveCurrentProfile() {
        let name = newProfileName
        ProfileController.shared.createFromCurrent(name: name) { message in
            if message.hasPrefix("Saved ") {
                newProfileName = ""
            }
        }
    }

    @ViewBuilder
    private func profileRow(_ profile: MenuBarProfile, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    if editingProfileID == profile.id {
                        TextField("Profile name", text: $editingName)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { finishEditing(profile.id) }
                    } else {
                        Text(profile.name)
                            .font(.headline)
                    }

                    Text("\(profile.placements.count) identifiable item"
                        + (profile.placements.count == 1 ? "" : "s"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if editingProfileID == profile.id {
                    Button("Save") {
                        finishEditing(profile.id)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("Cancel") {
                        cancelEditing()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    let isCurrent = controller.activeProfileID == profile.id
                    if isCurrent {
                        Button {} label: {
                            Label("Current", systemImage: "checkmark")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(true)
                    } else {
                        Button {
                            controller.apply(profile.id) { _ in }
                        } label: {
                            Label("Apply", systemImage: "arrow.right.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(controller.isBusy)
                    }

                    profileActionsMenu(profile, index: index)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func profileActionsMenu(
        _ profile: MenuBarProfile,
        index: Int
    ) -> some View {
        Menu {
            Button {
                controller.move(profile.id, by: -1)
            } label: {
                Label("Move Up", systemImage: "arrow.up")
            }
            .disabled(index == 0)

            Button {
                controller.move(profile.id, by: 1)
            } label: {
                Label("Move Down", systemImage: "arrow.down")
            }
            .disabled(index == controller.profiles.count - 1)

            Divider()

            Button {
                beginEditing(profile)
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button(role: .destructive) {
                profileToDelete = profile
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 20, height: 18)
        }
        .menuStyle(.borderedButton)
        .controlSize(.small)
        .help("More actions for \(profile.name)")
        .accessibilityLabel("More actions for \(profile.name)")
    }

    @ViewBuilder
    private func unresolvedList(
        title: String,
        placements: [ProfileItemPlacement]
    ) -> some View {
        DisclosureGroup("\(title) (\(placements.count))") {
            ForEach(placements) { placement in
                Text(placement.displayName)
                    .font(.caption)
            }
        }
    }

    private func finishEditing(_ profileID: UUID) {
        _ = controller.rename(profileID, to: editingName)
        cancelEditing()
    }

    private func beginEditing(_ profile: MenuBarProfile) {
        editingProfileID = profile.id
        editingName = profile.name
    }

    private func cancelEditing() {
        editingProfileID = nil
        editingName = ""
    }
}
