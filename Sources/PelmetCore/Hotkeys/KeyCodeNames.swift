/// Names for virtual keycodes.
///
/// The tables are transcribed from `Carbon.HIToolbox/Events.h`, with the `kVK_*`
/// constant named in a comment on each row, because PelmetCore must not import
/// Carbon. Two tiers on purpose:
///
/// - `specialName` covers keys whose label never changes with the keyboard
///   layout (positional and non-printable keys). Always consulted first: passing
///   an arrow or function keycode through `UCKeyTranslate` returns junk.
/// - `ansiName` covers characters on a US layout, and is a *fallback* only. The
///   app layer prefers the live layout, since the same position prints a
///   different character on Dvorak or a non-Latin input source.
public enum KeyCodeNames {

    /// The modifier keys themselves. A shortcut can never be one of these, so
    /// `KeyCombo.isPlausible` rejects them and the validator reports
    /// `.modifiersOnly`.
    public static let modifierKeyCodes: Set<UInt16> = [
        54,  // kVK_RightCommand
        55,  // kVK_Command
        56,  // kVK_Shift
        57,  // kVK_CapsLock
        58,  // kVK_Option
        59,  // kVK_Control
        60,  // kVK_RightShift
        61,  // kVK_RightOption
        62,  // kVK_RightControl
        63,  // kVK_Function
    ]

    /// Glyph shown for keys with no printable character. Function keys use their
    /// plain name ("F5") because macOS labels them that way.
    private static let specialNames: [UInt16: String] = [
        36: "↩",  // kVK_Return
        48: "⇥",  // kVK_Tab
        49: "Space",  // kVK_Space
        51: "⌫",  // kVK_Delete
        53: "⎋",  // kVK_Escape
        71: "⌧",  // kVK_ANSI_KeypadClear
        76: "⌤",  // kVK_ANSI_KeypadEnter
        114: "Help",  // kVK_Help
        115: "↖",  // kVK_Home
        116: "⇞",  // kVK_PageUp
        117: "⌦",  // kVK_ForwardDelete
        119: "↘",  // kVK_End
        121: "⇟",  // kVK_PageDown
        123: "←",  // kVK_LeftArrow
        124: "→",  // kVK_RightArrow
        125: "↓",  // kVK_DownArrow
        126: "↑",  // kVK_UpArrow
        122: "F1",  // kVK_F1
        120: "F2",  // kVK_F2
        99: "F3",  // kVK_F3
        118: "F4",  // kVK_F4
        96: "F5",  // kVK_F5
        97: "F6",  // kVK_F6
        98: "F7",  // kVK_F7
        100: "F8",  // kVK_F8
        101: "F9",  // kVK_F9
        109: "F10",  // kVK_F10
        103: "F11",  // kVK_F11
        111: "F12",  // kVK_F12
        105: "F13",  // kVK_F13
        107: "F14",  // kVK_F14
        113: "F15",  // kVK_F15
        106: "F16",  // kVK_F16
        64: "F17",  // kVK_F17
        79: "F18",  // kVK_F18
        80: "F19",  // kVK_F19
        90: "F20",  // kVK_F20
    ]

    /// Spoken equivalents for the glyphs above. VoiceOver reads "↩" and "⌫"
    /// poorly, so the accessibility path substitutes words.
    private static let specialSpokenNames: [UInt16: String] = [
        36: "Return",
        48: "Tab",
        49: "Space",
        51: "Delete",
        53: "Escape",
        71: "Clear",
        76: "Enter",
        114: "Help",
        115: "Home",
        116: "Page Up",
        117: "Forward Delete",
        119: "End",
        121: "Page Down",
        123: "Left Arrow",
        124: "Right Arrow",
        125: "Down Arrow",
        126: "Up Arrow",
    ]

    /// Characters a US layout prints for each position, uppercased for display.
    private static let ansiNames: [UInt16: String] = [
        0: "A",  // kVK_ANSI_A
        1: "S",  // kVK_ANSI_S
        2: "D",  // kVK_ANSI_D
        3: "F",  // kVK_ANSI_F
        4: "H",  // kVK_ANSI_H
        5: "G",  // kVK_ANSI_G
        6: "Z",  // kVK_ANSI_Z
        7: "X",  // kVK_ANSI_X
        8: "C",  // kVK_ANSI_C
        9: "V",  // kVK_ANSI_V
        10: "§",  // kVK_ISO_Section
        11: "B",  // kVK_ANSI_B
        12: "Q",  // kVK_ANSI_Q
        13: "W",  // kVK_ANSI_W
        14: "E",  // kVK_ANSI_E
        15: "R",  // kVK_ANSI_R
        16: "Y",  // kVK_ANSI_Y
        17: "T",  // kVK_ANSI_T
        18: "1",  // kVK_ANSI_1
        19: "2",  // kVK_ANSI_2
        20: "3",  // kVK_ANSI_3
        21: "4",  // kVK_ANSI_4
        22: "6",  // kVK_ANSI_6
        23: "5",  // kVK_ANSI_5
        24: "=",  // kVK_ANSI_Equal
        25: "9",  // kVK_ANSI_9
        26: "7",  // kVK_ANSI_7
        27: "-",  // kVK_ANSI_Minus
        28: "8",  // kVK_ANSI_8
        29: "0",  // kVK_ANSI_0
        30: "]",  // kVK_ANSI_RightBracket
        31: "O",  // kVK_ANSI_O
        32: "U",  // kVK_ANSI_U
        33: "[",  // kVK_ANSI_LeftBracket
        34: "I",  // kVK_ANSI_I
        35: "P",  // kVK_ANSI_P
        37: "L",  // kVK_ANSI_L
        38: "J",  // kVK_ANSI_J
        39: "'",  // kVK_ANSI_Quote
        40: "K",  // kVK_ANSI_K
        41: ";",  // kVK_ANSI_Semicolon
        42: "\\",  // kVK_ANSI_Backslash
        43: ",",  // kVK_ANSI_Comma
        44: "/",  // kVK_ANSI_Slash
        45: "N",  // kVK_ANSI_N
        46: "M",  // kVK_ANSI_M
        47: ".",  // kVK_ANSI_Period
        50: "`",  // kVK_ANSI_Grave
        65: "Num .",  // kVK_ANSI_KeypadDecimal
        67: "Num *",  // kVK_ANSI_KeypadMultiply
        69: "Num +",  // kVK_ANSI_KeypadPlus
        75: "Num /",  // kVK_ANSI_KeypadDivide
        78: "Num -",  // kVK_ANSI_KeypadMinus
        81: "Num =",  // kVK_ANSI_KeypadEquals
        82: "Num 0",  // kVK_ANSI_Keypad0
        83: "Num 1",  // kVK_ANSI_Keypad1
        84: "Num 2",  // kVK_ANSI_Keypad2
        85: "Num 3",  // kVK_ANSI_Keypad3
        86: "Num 4",  // kVK_ANSI_Keypad4
        87: "Num 5",  // kVK_ANSI_Keypad5
        88: "Num 6",  // kVK_ANSI_Keypad6
        89: "Num 7",  // kVK_ANSI_Keypad7
        91: "Num 8",  // kVK_ANSI_Keypad8
        92: "Num 9",  // kVK_ANSI_Keypad9
        93: "¥",  // kVK_JIS_Yen
        94: "_",  // kVK_JIS_Underscore
        95: "Num ,",  // kVK_JIS_KeypadComma
    ]

    public static func specialName(for keyCode: UInt16) -> String? {
        specialNames[keyCode]
    }

    public static func specialSpokenName(for keyCode: UInt16) -> String? {
        specialSpokenNames[keyCode] ?? specialNames[keyCode]
    }

    public static func ansiName(for keyCode: UInt16) -> String? {
        ansiNames[keyCode]
    }

    public static func displayName(for keyCode: UInt16) -> String? {
        specialName(for: keyCode) ?? ansiName(for: keyCode)
    }

    public static func spokenName(for keyCode: UInt16) -> String? {
        specialSpokenName(for: keyCode) ?? ansiName(for: keyCode)
    }

    /// Whether this position prints a character.
    ///
    /// This drives the two-modifier rule in `HotkeyValidator`: a global ⌘B would
    /// consume ⌘B in every app on the system, but a global ⌘F5 costs nothing,
    /// because no app binds a bare function key to something the user needs.
    /// Delete counts as printable so ⌘⌫ ("Move to Trash") stays out of reach.
    public static func isPrintable(_ keyCode: UInt16) -> Bool {
        if modifierKeyCodes.contains(keyCode) { return false }
        if ansiNames[keyCode] != nil { return true }
        switch keyCode {
        case 36, 48, 49, 51, 76, 117:  // Return, Tab, Space, Delete, Enter, Forward Delete
            return true
        default:
            return false
        }
    }
}
