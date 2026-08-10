/// The things a global shortcut can do in Pelmet.
///
/// Deliberately closed and small. Both actions have a click path and a
/// right-click menu path too, so a cleared shortcut never strands the user.
public enum HotkeyAction: String, CaseIterable, Codable, Hashable, Sendable {

    case toggle
    case shelf

    /// Carbon's `EventHotKeyID.id`. Frozen at the values used before shortcuts
    /// became customizable, so the trampoline's wire format did not change.
    public var eventID: UInt32 {
        switch self {
        case .toggle: return 1
        case .shelf: return 2
        }
    }

    /// Settings row label, and the subject of a rejection sentence.
    public var title: String {
        switch self {
        case .toggle: return "Hide and show icons"
        case .shelf: return "Open the Shelf"
        }
    }

    /// What Pelmet has always shipped: ⌥⌘B and ⌥⌘N.
    public var defaultCombo: KeyCombo {
        switch self {
        case .toggle: return KeyCombo(keyCode: 11, modifiers: [.option, .command])  // kVK_ANSI_B
        case .shelf: return KeyCombo(keyCode: 45, modifiers: [.option, .command])  // kVK_ANSI_N
        }
    }
}

/// What every action is bound to right now.
///
/// A nil combo means the user deliberately cleared that shortcut. The chevron
/// click and the right-click menu still reach both actions, so clearing is a
/// safe thing to allow.
public struct HotkeyBindings: Equatable, Sendable {

    public var toggle: KeyCombo?
    public var shelf: KeyCombo?

    public init(toggle: KeyCombo?, shelf: KeyCombo?) {
        self.toggle = toggle
        self.shelf = shelf
    }

    public static let defaults = HotkeyBindings(
        toggle: HotkeyAction.toggle.defaultCombo,
        shelf: HotkeyAction.shelf.defaultCombo
    )

    public subscript(action: HotkeyAction) -> KeyCombo? {
        get {
            switch action {
            case .toggle: return toggle
            case .shelf: return shelf
            }
        }
        set {
            switch action {
            case .toggle: toggle = newValue
            case .shelf: shelf = newValue
            }
        }
    }

    /// The *other* action already using `combo`, if any. Re-recording an action's
    /// own current shortcut is not a conflict, so the user can confirm what they
    /// already have without seeing an error.
    public func conflictingAction(
        with combo: KeyCombo,
        assigningTo action: HotkeyAction
    ) -> HotkeyAction? {
        HotkeyAction.allCases.first { $0 != action && self[$0] == combo }
    }
}
