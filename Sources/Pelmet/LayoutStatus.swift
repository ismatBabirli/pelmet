import AppKit
import Combine

/// Bridges live layout facts from MenuBarManager (AppKit) into SwiftUI
/// surfaces (Settings, Make Room window).
final class LayoutStatus: ObservableObject {

    static let shared = LayoutStatus()

    @Published var swallowedCount = 0
    @Published var hasNotchedDisplay: Bool
    @Published var spacingProfile: MenuBarSpacing.Profile

    private init() {
        hasNotchedDisplay = NSScreen.screens.contains { $0.safeAreaInsets.top > 0 }
        spacingProfile = MenuBarSpacing.currentProfile()
    }

    func refresh(swallowedCount: Int) {
        self.swallowedCount = swallowedCount
        hasNotchedDisplay = NSScreen.screens.contains { $0.safeAreaInsets.top > 0 }
    }

    func refreshSpacing() {
        spacingProfile = MenuBarSpacing.currentProfile()
    }
}
