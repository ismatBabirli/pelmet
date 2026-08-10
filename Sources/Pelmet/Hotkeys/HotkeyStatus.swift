import Foundation
import PelmetCore

extension Notification.Name {
    /// Posted whenever the bindings, their registration outcomes, or the keyboard
    /// layout that labels them changes.
    static let pelmetHotkeyBindingsDidChange = Notification.Name("PelmetHotkeyBindingsDidChange")
}

/// SwiftUI-observable mirror of the hotkey layer, so the Settings pane renders
/// registration failures and layout changes live. Same shape as `ActivationStatus`.
final class HotkeyStatus: ObservableObject {

    static let shared = HotkeyStatus()

    @Published private(set) var bindings: HotkeyBindings
    @Published private(set) var outcomes: [HotkeyAction: HotkeyManager.Outcome]
    /// Bumped when the input source changes. Nothing reads the value; it exists so
    /// a view that renders a cached glyph is invalidated.
    @Published private(set) var layoutGeneration = 0

    private init() {
        bindings = HotkeyManager.shared.bindings
        outcomes = HotkeyManager.shared.outcomes
        NotificationCenter.default.addObserver(
            forName: .pelmetHotkeyBindingsDidChange,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    /// True when nothing has been customized, so "Restore Defaults" can disable
    /// itself rather than pretend to be actionable.
    var isDefault: Bool {
        bindings == .defaults
    }

    private func refresh() {
        bindings = HotkeyManager.shared.bindings
        outcomes = HotkeyManager.shared.outcomes
        layoutGeneration = KeyboardLayoutNames.shared.generation
    }
}
