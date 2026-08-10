import AppKit
import PelmetCore

/// Renders a stored shortcut for every surface that quotes one: the Settings
/// recorder, the status-item tooltips, the right-click menu and the onboarding
/// copy.
///
/// Resolution order is deliberate. `KeyCodeNames.specialName` comes first,
/// because passing an arrow or function keycode through `UCKeyTranslate` returns
/// junk. Then the live layout, then PelmetCore's ANSI table, then a numeric last
/// resort so a label is never blank.
enum HotkeyDisplay {

    /// e.g. "⌥⌘B".
    static func string(for combo: KeyCombo) -> String {
        combo.displayString(keyName: keyName(for: combo))
    }

    /// e.g. "Option Command B", for VoiceOver.
    static func spoken(for combo: KeyCombo) -> String {
        combo.accessibilityDescription(keyName: keyName(for: combo))
    }

    /// The live layout's character for this position, or nil to let PelmetCore
    /// fall back to its own tables.
    static func keyName(for combo: KeyCombo) -> String? {
        if KeyCodeNames.specialName(for: combo.keyCode) != nil { return nil }
        return KeyboardLayoutNames.shared.characterName(for: combo.keyCode)
    }

    /// " (⌥⌘B)", or "" when the action has no shortcut. Lets a sentence quote the
    /// shortcut without needing a second variant for the cleared case.
    static func parenthetical(for combo: KeyCombo?) -> String {
        guard let combo else { return "" }
        return " (\(string(for: combo)))"
    }

    /// What `NSMenuItem` needs, which is a *character* rather than a keycode.
    ///
    /// The character must be lowercase: an uppercase `keyEquivalent` makes AppKit
    /// imply and then require a ⇧ that the user never chose. Non-printable keys
    /// use the `NS*FunctionKey` values. An empty string means "no accelerator",
    /// which is the honest rendering for a key we cannot name.
    static func menuKeyEquivalent(
        for combo: KeyCombo?
    ) -> (key: String, mask: NSEvent.ModifierFlags) {
        guard let combo else { return ("", []) }
        return (menuCharacter(for: combo), combo.modifiers.nsEventFlags)
    }

    private static func menuCharacter(for combo: KeyCombo) -> String {
        if let scalar = functionKeyScalar(for: combo.keyCode) {
            return String(scalar)
        }
        let name = keyName(for: combo) ?? KeyCodeNames.ansiName(for: combo.keyCode) ?? ""
        // Multi-character labels ("Num 5") have no single key equivalent.
        return name.count == 1 ? name.lowercased() : ""
    }

    private static func functionKeyScalar(for keyCode: UInt16) -> Character? {
        let functionKeys: [UInt16: Int] = [
            36: 0x000D,  // Return
            48: 0x0009,  // Tab
            49: 0x0020,  // Space
            51: NSDeleteCharacter,
            53: 0x001B,  // Escape
            71: NSClearLineFunctionKey,
            76: 0x0003,  // Keypad Enter
            114: NSHelpFunctionKey,
            115: NSHomeFunctionKey,
            116: NSPageUpFunctionKey,
            117: NSDeleteFunctionKey,
            119: NSEndFunctionKey,
            121: NSPageDownFunctionKey,
            123: NSLeftArrowFunctionKey,
            124: NSRightArrowFunctionKey,
            125: NSDownArrowFunctionKey,
            126: NSUpArrowFunctionKey,
            122: NSF1FunctionKey,
            120: NSF2FunctionKey,
            99: NSF3FunctionKey,
            118: NSF4FunctionKey,
            96: NSF5FunctionKey,
            97: NSF6FunctionKey,
            98: NSF7FunctionKey,
            100: NSF8FunctionKey,
            101: NSF9FunctionKey,
            109: NSF10FunctionKey,
            103: NSF11FunctionKey,
            111: NSF12FunctionKey,
            105: NSF13FunctionKey,
            107: NSF14FunctionKey,
            113: NSF15FunctionKey,
            106: NSF16FunctionKey,
            64: NSF17FunctionKey,
            79: NSF18FunctionKey,
            80: NSF19FunctionKey,
            90: NSF20FunctionKey,
        ]
        guard let value = functionKeys[keyCode],
              let scalar = Unicode.Scalar(UInt32(value))
        else { return nil }
        return Character(scalar)
    }
}
