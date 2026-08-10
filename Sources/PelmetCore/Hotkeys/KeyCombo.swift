/// Modifier keys, in Pelmet's own bits.
///
/// Deliberately not Carbon's `cmdKey`/`optionKey` values and not
/// `NSEvent.ModifierFlags`: PelmetCore imports neither Carbon nor AppKit, and a
/// persisted value must not depend on a framework constant that could change
/// meaning. The two adapters live in `Sources/Pelmet/Hotkeys/HotkeyCarbonBridge.swift`.
///
/// Bit order matches the macOS display order (⌃⌥⇧⌘) so `displayString` walks a
/// single table instead of reordering.
public struct KeyModifiers: OptionSet, Codable, Hashable, Sendable {

    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let control = KeyModifiers(rawValue: 1 << 0)
    public static let option = KeyModifiers(rawValue: 1 << 1)
    public static let shift = KeyModifiers(rawValue: 1 << 2)
    public static let command = KeyModifiers(rawValue: 1 << 3)

    /// Every bit Pelmet understands. Unknown future bits are masked off on
    /// decode, so a value written by a newer build degrades to something
    /// meaningful instead of registering a modifier set nobody chose.
    public static let all: KeyModifiers = [.control, .option, .shift, .command]

    /// At least one of these is required for a global shortcut: ⇧ alone would
    /// swallow ordinary typing everywhere.
    public static let primary: KeyModifiers = [.control, .option, .command]

    /// ⌃⌥⇧⌘, the order macOS itself uses. Spoken names are for VoiceOver, which
    /// reads the glyphs poorly.
    private static let displayOrder: [(flag: KeyModifiers, glyph: String, spoken: String)] = [
        (.control, "⌃", "Control"),
        (.option, "⌥", "Option"),
        (.shift, "⇧", "Shift"),
        (.command, "⌘", "Command"),
    ]

    /// Encoded as a bare number rather than `{"rawValue": n}`, so `defaults read`
    /// stays readable during support triage.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(UInt32.self)
        self.rawValue = raw & KeyModifiers.all.rawValue
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// e.g. "⌥⌘".
    public var displayString: String {
        KeyModifiers.displayOrder.reduce(into: "") { result, entry in
            if contains(entry.flag) { result += entry.glyph }
        }
    }

    /// e.g. "Option Command".
    public var spokenString: String {
        KeyModifiers.displayOrder
            .filter { contains($0.flag) }
            .map(\.spoken)
            .joined(separator: " ")
    }
}

/// One global shortcut: a physical key position plus its modifiers.
///
/// `keyCode` is a *virtual keycode*, meaning a physical position, because that is
/// what Carbon's `RegisterEventHotKey` takes. It is deliberately NOT a character:
/// on Dvorak the key labelled X reports the ANSI-B keycode, and the hotkey has to
/// follow the physical key the user actually pressed. The consequence is that
/// display is layout dependent while storage is not.
public struct KeyCombo: Codable, Equatable, Hashable, Sendable {

    public let keyCode: UInt16
    public let modifiers: KeyModifiers

    public init(keyCode: UInt16, modifiers: KeyModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(.all)
    }

    private enum CodingKeys: String, CodingKey {
        case keyCode
        case modifiers
    }

    /// Carbon accepts virtual keycodes in 0...127. Anything outside that range,
    /// or a modifier key on its own, is a value Pelmet could not have produced,
    /// so callers treat it as corrupt rather than registering it.
    public var isPlausible: Bool {
        keyCode <= 127 && !KeyCodeNames.modifierKeyCodes.contains(keyCode)
    }

    /// e.g. "⌥⌘B". `keyName` lets the app layer substitute the character the
    /// user's live keyboard layout prints; nil falls back to the ANSI-US table.
    public func displayString(keyName: String? = nil) -> String {
        modifiers.displayString + resolvedKeyName(keyName)
    }

    /// e.g. "Option Command B", for VoiceOver.
    public func accessibilityDescription(keyName: String? = nil) -> String {
        let spokenKey = KeyCodeNames.spokenName(for: keyCode)
            ?? keyName
            ?? resolvedKeyName(keyName)
        let spokenModifiers = modifiers.spokenString
        return spokenModifiers.isEmpty ? spokenKey : "\(spokenModifiers) \(spokenKey)"
    }

    private func resolvedKeyName(_ keyName: String?) -> String {
        if let special = KeyCodeNames.specialName(for: keyCode) { return special }
        return keyName ?? KeyCodeNames.ansiName(for: keyCode) ?? "Key \(keyCode)"
    }
}
