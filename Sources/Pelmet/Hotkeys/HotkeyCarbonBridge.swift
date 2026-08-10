import AppKit
import Carbon.HIToolbox
import PelmetCore

/// Adapters between PelmetCore's framework-free `KeyModifiers` and the two APIs
/// that actually consume them. PelmetCore deliberately owns neither, so both
/// conversions live here.
extension KeyModifiers {

    /// The mask `RegisterEventHotKey` takes.
    var carbonFlags: UInt32 {
        var flags: UInt32 = 0
        if contains(.command) { flags |= UInt32(cmdKey) }
        if contains(.option) { flags |= UInt32(optionKey) }
        if contains(.control) { flags |= UInt32(controlKey) }
        if contains(.shift) { flags |= UInt32(shiftKey) }
        return flags
    }

    /// The mask an `NSMenuItem` takes.
    var nsEventFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if contains(.command) { flags.insert(.command) }
        if contains(.option) { flags.insert(.option) }
        if contains(.control) { flags.insert(.control) }
        if contains(.shift) { flags.insert(.shift) }
        return flags
    }

    /// Reads the four modifiers a user can choose out of a live event.
    ///
    /// Testing the four bits explicitly matters: `deviceIndependentFlagsMask`
    /// alone is not enough, because AppKit also reports `.function` and
    /// `.numericPad` on arrows and function keys, and `.capsLock` whenever Caps
    /// Lock happens to be on. Masking loosely would record ⌥⌘→ as four modifiers.
    init(nsEventFlags: NSEvent.ModifierFlags) {
        var modifiers: KeyModifiers = []
        if nsEventFlags.contains(.command) { modifiers.insert(.command) }
        if nsEventFlags.contains(.option) { modifiers.insert(.option) }
        if nsEventFlags.contains(.control) { modifiers.insert(.control) }
        if nsEventFlags.contains(.shift) { modifiers.insert(.shift) }
        self = modifiers
    }

    /// Reads Carbon's own mask, for the symbolic hotkeys macOS reports.
    init(carbonFlags: UInt32) {
        var modifiers: KeyModifiers = []
        if carbonFlags & UInt32(cmdKey) != 0 { modifiers.insert(.command) }
        if carbonFlags & UInt32(optionKey) != 0 { modifiers.insert(.option) }
        if carbonFlags & UInt32(controlKey) != 0 { modifiers.insert(.control) }
        if carbonFlags & UInt32(shiftKey) != 0 { modifiers.insert(.shift) }
        self = modifiers
    }
}
