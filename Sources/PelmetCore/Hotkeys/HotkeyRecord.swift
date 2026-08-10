/// The persisted form of one action's shortcut.
///
/// Follows the `UpdateRetrySnapshot` precedent: stored as JSON under its own
/// UserDefaults key, and absent or undecodable means "use the shipped default".
/// So an existing install keeps ⌥⌘B and ⌥⌘N with no migration step, a corrupt
/// value can never leave the user without a shortcut, and a future change of
/// default still reaches everyone who never customized.
public struct HotkeyRecord: Codable, Equatable, Sendable {

    /// nil means the user cleared the shortcut ON PURPOSE. That is a different
    /// fact from the whole key being absent, which means "never touched", and the
    /// two have to resolve differently.
    public var keyCode: UInt16?
    public var modifiers: KeyModifiers

    public init(combo: KeyCombo?) {
        self.keyCode = combo?.keyCode
        self.modifiers = combo?.modifiers ?? []
    }

    public var combo: KeyCombo? {
        keyCode.map { KeyCombo(keyCode: $0, modifiers: modifiers) }
    }

    private enum CodingKeys: String, CodingKey {
        case keyCode
        case modifiers
    }
}

/// Collapses a stored record into the shortcut actually in force.
///
/// Kept separate from `Preferences` so the three-state logic is unit-testable
/// without touching UserDefaults.
public enum HotkeyBindingResolver {

    /// - nil record (key absent, or JSON that would not decode) means the
    ///   shipped default.
    /// - A record with no keyCode means nil: cleared on purpose.
    /// - A record whose keyCode Carbon could not accept means the shipped
    ///   default, because registering it would silently do nothing.
    public static func resolve(_ record: HotkeyRecord?, for action: HotkeyAction) -> KeyCombo? {
        guard let record else { return action.defaultCombo }
        guard let combo = record.combo else { return nil }
        return combo.isPlausible ? combo : action.defaultCombo
    }

    public static func resolve(
        toggle: HotkeyRecord?,
        shelf: HotkeyRecord?
    ) -> HotkeyBindings {
        HotkeyBindings(
            toggle: resolve(toggle, for: .toggle),
            shelf: resolve(shelf, for: .shelf)
        )
    }
}
