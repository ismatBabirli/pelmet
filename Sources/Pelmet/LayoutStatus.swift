import AppKit
import Combine
import PelmetCore

/// Bridges live layout facts from MenuBarManager (AppKit) into SwiftUI
/// surfaces (Settings, Make Room window, the Shelf).
final class LayoutStatus: ObservableObject {

    static let shared = LayoutStatus()

    @Published var swallowedCount = 0
    @Published var hasNotchedDisplay: Bool
    @Published var hasMenuBarObstruction: Bool
    @Published var spacingProfile: MenuBarSpacing.Profile
    /// One row per icon the notch hid — same source of truth as
    /// `swallowedCount` (badge parity).
    @Published var shelfEntries: [ShelfEntryModel] = []
    private var softwareIslandObservation: AnyCancellable?

    private init() {
        let softwareIslands = SoftwareIslandMonitor.shared
        softwareIslands.refresh()
        let hasPhysicalNotch = NSScreen.screens.contains { $0.safeAreaInsets.top > 0 }
        hasNotchedDisplay = hasPhysicalNotch
        hasMenuBarObstruction = hasPhysicalNotch
            || softwareIslands.hasEnabledCandidate
        spacingProfile = MenuBarSpacing.currentProfile()

        // Candidate lifecycle is independent of the layout digest. In
        // particular, launching or quitting an island while Pelmet is
        // collapsed can leave the icon count unchanged, so observe discovery
        // directly instead of waiting for MenuBarManager.apply().
        softwareIslandObservation = softwareIslands.$candidates
            .map { candidates in
                NSScreen.screens.contains { $0.safeAreaInsets.top > 0 }
                    || candidates.contains(where: \.enabled)
            }
            .removeDuplicates()
            .sink { [weak self] hasObstruction in
                self?.hasMenuBarObstruction = hasObstruction
            }
    }

    func refresh(swallowedCount: Int, shelfEntries: [ShelfEntryModel]) {
        self.swallowedCount = swallowedCount
        self.shelfEntries = shelfEntries
        hasNotchedDisplay = NSScreen.screens.contains { $0.safeAreaInsets.top > 0 }
        hasMenuBarObstruction = hasNotchedDisplay
            || SoftwareIslandMonitor.shared.hasEnabledCandidate
    }

    func refreshSpacing() {
        spacingProfile = MenuBarSpacing.currentProfile()
    }
}
