import Combine
import SwiftUI

/// System Settings-style two-column layout: a sidebar of panes on the left,
/// the selected pane's form on the right. The window uses a transparent
/// full-size titlebar, so the sidebar material runs to the top edge and the
/// pane title (not the window title) names what you're looking at.
struct SettingsRootView: View {

    @ObservedObject private var status = LayoutStatus.shared
    @State private var selection: SettingsPane =
        SettingsPane(rawValue: Preferences.settingsPane) ?? .general

    var body: some View {
        let available = SettingsPane.available(hasNotchedDisplay: status.hasNotchedDisplay)
        // Render a valid pane even before onReceive normalizes a stale
        // selection (e.g. "oneClickAccess" persisted on a non-notched Mac).
        let shown = available.contains(selection) ? selection : .general

        HStack(spacing: 0) {
            List(available, selection: Binding(
                // Setter side effect instead of .onChange —
                // the non-deprecated onChange(of:initial:_:) needs macOS 14.
                get: { Optional(shown) },
                set: { pane in
                    guard let pane else { return }
                    selection = pane
                    Preferences.settingsPane = pane.rawValue
                }
            )) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    Image(systemName: pane.symbolName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(pane.tint.gradient)
                        )
                }
                .tag(pane)
            }
            .listStyle(.sidebar)
            // Keep the first row clear of the traffic lights, which overlay
            // the sidebar because the titlebar is transparent.
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: 36)
            }
            .frame(width: SettingsPane.sidebarWidth)

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                Text(shown.title)
                    .font(.title2.bold())
                    .padding(.top, 34)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 2)
                detail(for: shown)
            }
            .frame(width: SettingsPane.detailWidth)
        }
        // The titlebar area belongs to the layout (System Settings look);
        // the paddings above compensate for it.
        .ignoresSafeArea(.container, edges: .top)
        .frame(height: SettingsPane.contentHeight)
        // If One-Click Access vanishes while selected (lid closed on a
        // notched MacBook driving an external display), fall back to General.
        // removeDuplicates is mandatory: LayoutStatus re-assigns
        // hasNotchedDisplay on every layout snapshot.
        .onReceive(LayoutStatus.shared.$hasNotchedDisplay.removeDuplicates()) { hasNotch in
            if !SettingsPane.available(hasNotchedDisplay: hasNotch).contains(selection) {
                selection = .general
            }
        }
    }

    @ViewBuilder
    private func detail(for pane: SettingsPane) -> some View {
        switch pane {
        case .general: GeneralPaneView()
        case .menuBarSpace: MenuBarSpacePaneView()
        case .oneClickAccess: OneClickAccessPaneView()
        }
    }
}
