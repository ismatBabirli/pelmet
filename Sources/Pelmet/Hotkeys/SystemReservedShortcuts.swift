import Carbon.HIToolbox
import Foundation
import PelmetCore

/// Reads macOS's own symbolic hotkeys, so a combination the user *remapped* in
/// Keyboard Settings is refused too, which a static table cannot know.
///
/// Permission free: `CopySymbolicHotKeys` is a read-only Carbon call, so this
/// does not touch the zero-permission core.
///
/// The live read cannot say what owns a combination (the API reports numeric
/// symbolic IDs), so its refusals read "macOS already uses this shortcut" while
/// PelmetCore's hand-written table names Spotlight, the Dock and the rest.
/// Merging keeps the better sentence wherever we have one and still catches
/// remapped and non-default system shortcuts.
enum SystemReservedShortcuts {

    private static let genericOwner = "macOS"

    /// PelmetCore's static table with the live read merged in. Static entries
    /// win, for their owner names. Any failure reading the system list returns
    /// just the static table, which degrades to exactly the behaviour Pelmet
    /// would have had without this step.
    static func current() -> [ReservedCombo] {
        var merged = HotkeyValidator.systemReserved
        let known = Set(merged.map(\.combo))
        for combo in liveSymbolicHotkeys() where !known.contains(combo) {
            merged.append(ReservedCombo(combo: combo, owner: genericOwner))
        }
        return merged
    }

    private static func liveSymbolicHotkeys() -> [KeyCombo] {
        var unmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanaged) == noErr,
              let entries = unmanaged?.takeRetainedValue() as? [[String: Any]]
        else { return [] }

        return entries.compactMap { entry in
            // A disabled symbolic hotkey is not reserved: the user turned it off.
            guard let enabled = entry[kHISymbolicHotKeyEnabled as String] as? Bool, enabled,
                  let keyCode = entry[kHISymbolicHotKeyCode as String] as? Int,
                  let carbonModifiers = entry[kHISymbolicHotKeyModifiers as String] as? Int,
                  keyCode >= 0, keyCode <= 127
            else { return nil }
            return KeyCombo(
                keyCode: UInt16(keyCode),
                modifiers: KeyModifiers(carbonFlags: UInt32(bitPattern: Int32(carbonModifiers)))
            )
        }
    }
}
