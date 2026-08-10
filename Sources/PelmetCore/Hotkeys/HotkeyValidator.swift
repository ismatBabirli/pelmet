/// Why a recorded combination was refused. Each case maps to one sentence, so
/// the recorder can tell the user exactly what is wrong instead of just beeping.
public enum HotkeyRejection: Equatable, Sendable {

    /// The key pressed was a modifier key itself.
    case modifiersOnly
    /// No ⌘, ⌥ or ⌃ at all. ⇧ alone (or nothing) would capture ordinary typing.
    case noPrimaryModifier
    /// One modifier plus a character key.
    case needsSecondModifier
    /// macOS owns this combination.
    case systemReserved(owner: String)
    /// Pelmet's other action already uses it.
    case alreadyAssigned(HotkeyAction)
    /// A keycode Carbon cannot register.
    case unsupportedKey

    /// One sentence, ready to render under the row. `keyName` lets the app layer
    /// name the key the user's live layout prints, so a Dvorak user is told about
    /// the key they actually pressed.
    public func message(for combo: KeyCombo, keyName: String? = nil) -> String {
        let shortcut = combo.displayString(keyName: keyName)
        switch self {
        case .modifiersOnly:
            return "That is a modifier on its own. Hold your modifiers, then press a letter, "
                + "number or function key."
        case .noPrimaryModifier:
            return "Add ⌘, ⌥ or ⌃. Shift on its own would capture ordinary typing."
        case .needsSecondModifier:
            return "\(shortcut) needs one more modifier. A single modifier plus a character key "
                + "would override that combination in every app."
        case let .systemReserved(owner):
            return "\(owner) already uses \(shortcut). Pick a different combination."
        case let .alreadyAssigned(action):
            return "\(shortcut) is already used by \"\(action.title)\"."
        case .unsupportedKey:
            return "Pelmet cannot use that key. Try a letter, number or function key."
        }
    }
}

/// A combination macOS itself owns, with a name for the sentence.
public struct ReservedCombo: Equatable, Sendable {

    public let combo: KeyCombo
    /// What owns it, phrased to drop into "X already uses ⌘Space."
    public let owner: String

    public init(combo: KeyCombo, owner: String) {
        self.combo = combo
        self.owner = owner
    }
}

/// Decides whether a recorded combination is usable as a global shortcut.
///
/// Pure, with every fact injected: the reserved list is a parameter so the app
/// layer can merge in a live `CopySymbolicHotKeys` read without this module
/// learning about Carbon.
public enum HotkeyValidator {

    /// Combinations macOS owns.
    ///
    /// Deliberately short. Rule 2 in `validate` already refuses every single
    /// modifier plus a character key (⌘Q, ⌘W, ⌘comma, ⌘H, ⌘C and the rest), so
    /// this table only needs the combinations that would otherwise *pass*, plus
    /// the handful where naming the real owner reads far better than "add another
    /// modifier". The app layer merges the user's live symbolic hotkeys on top.
    public static let systemReserved: [ReservedCombo] = [
        ReservedCombo(combo: KeyCombo(keyCode: 49, modifiers: [.command]), owner: "Spotlight"),
        ReservedCombo(
            combo: KeyCombo(keyCode: 49, modifiers: [.control, .command]),
            owner: "Emoji & Symbols"
        ),
        ReservedCombo(
            combo: KeyCombo(keyCode: 49, modifiers: [.control]),
            owner: "The input source switcher"
        ),
        ReservedCombo(
            combo: KeyCombo(keyCode: 49, modifiers: [.control, .option]),
            owner: "The input source switcher"
        ),
        ReservedCombo(
            combo: KeyCombo(keyCode: 48, modifiers: [.command]),
            owner: "The app switcher"
        ),
        ReservedCombo(
            combo: KeyCombo(keyCode: 48, modifiers: [.shift, .command]),
            owner: "The app switcher"
        ),
        ReservedCombo(
            combo: KeyCombo(keyCode: 50, modifiers: [.command]),
            owner: "The window switcher"
        ),
        ReservedCombo(
            combo: KeyCombo(keyCode: 50, modifiers: [.shift, .command]),
            owner: "The window switcher"
        ),
        ReservedCombo(
            combo: KeyCombo(keyCode: 53, modifiers: [.option, .command]),
            owner: "Force Quit"
        ),
        ReservedCombo(
            combo: KeyCombo(keyCode: 12, modifiers: [.control, .command]),
            owner: "Lock Screen"
        ),
        ReservedCombo(
            combo: KeyCombo(keyCode: 3, modifiers: [.control, .command]),
            owner: "Enter Full Screen"
        ),
        ReservedCombo(
            combo: KeyCombo(keyCode: 20, modifiers: [.shift, .command]),
            owner: "Screenshot"
        ),
        ReservedCombo(
            combo: KeyCombo(keyCode: 21, modifiers: [.shift, .command]),
            owner: "Screenshot"
        ),
        ReservedCombo(
            combo: KeyCombo(keyCode: 23, modifiers: [.shift, .command]),
            owner: "Screenshot"
        ),
        ReservedCombo(
            combo: KeyCombo(keyCode: 126, modifiers: [.control]),
            owner: "Mission Control"
        ),
        ReservedCombo(combo: KeyCombo(keyCode: 125, modifiers: [.control]), owner: "App Exposé"),
        ReservedCombo(
            combo: KeyCombo(keyCode: 123, modifiers: [.control]),
            owner: "Switching Spaces"
        ),
        ReservedCombo(
            combo: KeyCombo(keyCode: 124, modifiers: [.control]),
            owner: "Switching Spaces"
        ),
        ReservedCombo(
            combo: KeyCombo(keyCode: 2, modifiers: [.option, .command]),
            owner: "The Dock"
        ),
    ]

    /// nil means the combination is acceptable.
    ///
    /// The reserved list is consulted before the modifier rules so ⌘Space reports
    /// "Spotlight already uses ⌘Space" rather than the vaguer "needs one more
    /// modifier".
    public static func validate(
        _ combo: KeyCombo,
        for action: HotkeyAction,
        against bindings: HotkeyBindings,
        systemReserved: [ReservedCombo] = HotkeyValidator.systemReserved
    ) -> HotkeyRejection? {
        if KeyCodeNames.modifierKeyCodes.contains(combo.keyCode) { return .modifiersOnly }
        if !combo.isPlausible { return .unsupportedKey }

        if let reserved = systemReserved.first(where: { $0.combo == combo }) {
            return .systemReserved(owner: reserved.owner)
        }

        if combo.modifiers.isDisjoint(with: .primary) { return .noPrimaryModifier }

        // A Carbon hotkey consumes its keystroke system wide, so a single
        // modifier on a character key would take that combination away from
        // every app: ⌘Q would stop quitting anything. Positional keys (function
        // keys, arrows, Escape) cost nothing, so one modifier is enough there.
        if KeyCodeNames.isPrintable(combo.keyCode), combo.modifiers.rawValue.nonzeroBitCount < 2 {
            return .needsSecondModifier
        }

        if let other = bindings.conflictingAction(with: combo, assigningTo: action) {
            return .alreadyAssigned(other)
        }

        return nil
    }
}
