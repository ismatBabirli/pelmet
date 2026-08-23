import SwiftUI
import PelmetCore

/// The sidebar entries of the Settings window. Raw values are persisted
/// (`Preferences.settingsPane`) — don't rename cases casually.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case menuBarSpace
    case oneClickAccess
    case about

    var id: String { rawValue }

    /// Sidebar column width; the detail column holds the pane forms.
    static let sidebarWidth: CGFloat = 200
    static let detailWidth: CGFloat = 420
    /// Total window content height — sized so the tallest pane (General)
    /// fits scroll-free; panes scroll if they ever outgrow it.
    static let contentHeight: CGFloat = 560

    /// One-Click Access appears when an obstruction makes it relevant and
    /// remains available while enabled, even if that obstruction's app quits.
    static func available(
        hasMenuBarObstruction: Bool,
        oneClickAccessEnabled: Bool
    ) -> [SettingsPane] {
        OneClickAccessPanePolicy.isAvailable(
            hasMenuBarObstruction: hasMenuBarObstruction,
            isEnabled: oneClickAccessEnabled
        ) ? allCases : [.general, .menuBarSpace, .about]
    }

    var title: String {
        switch self {
        case .general: return "General"
        case .menuBarSpace: return "Menu Bar Space"
        case .oneClickAccess: return "One-Click Access"
        case .about: return "About"
        }
    }

    var symbolName: String {
        switch self {
        case .general: return "gearshape"
        case .menuBarSpace: return "menubar.rectangle"
        case .oneClickAccess: return "cursorarrow.click"
        case .about: return "info.circle"
        }
    }

    /// Fill of the System Settings-style icon tile in the sidebar.
    var tint: Color {
        switch self {
        case .general: return .gray
        case .menuBarSpace: return .blue
        case .oneClickAccess: return .purple
        case .about: return .teal
        }
    }
}
