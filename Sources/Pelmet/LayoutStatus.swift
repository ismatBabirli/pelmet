import AppKit
import Combine
import PelmetCore

/// Bridges live layout facts from MenuBarManager (AppKit) into SwiftUI
/// surfaces (Settings, Make Room window, the Shelf).
final class LayoutStatus: ObservableObject {

    static let shared = LayoutStatus()

    @Published var swallowedCount = 0
    @Published var hasNotchedDisplay: Bool
    @Published var spacingProfile: MenuBarSpacing.Profile
    /// One row per icon the notch hid — same source of truth as
    /// `swallowedCount` (badge parity).
    @Published var shelfEntries: [ShelfEntryModel] = []

    private init() {
        hasNotchedDisplay = NSScreen.screens.contains { $0.safeAreaInsets.top > 0 }
        spacingProfile = MenuBarSpacing.currentProfile()
    }

    func refresh(swallowedCount: Int, shelfEntries: [ShelfEntryModel]) {
        self.swallowedCount = swallowedCount
        self.shelfEntries = shelfEntries
        hasNotchedDisplay = NSScreen.screens.contains { $0.safeAreaInsets.top > 0 }
    }

    func refreshSpacing() {
        spacingProfile = MenuBarSpacing.currentProfile()
    }
}
