import AppKit

/// Moves one of Pelmet's OWN status items by recreating it at a seeded
/// position — the only sanctioned way to reposition a status item without
/// the Accessibility permission.
///
/// The order of operations is load-bearing:
///  1. `removeStatusItem` DELETES the "NSStatusItem Preferred Position"
///     default as a side effect, so the new position must be written AFTER
///     removal and BEFORE creation (write-then-create is how macOS reads it).
///  2. `isVisible = false` is never used — it also deletes the default and
///     loses the position permanently (FB9052637).
///
/// Positions are order hints, not coordinates: on a crowded bar macOS packs
/// items and only preserves relative order (verified empirically), so
/// callers pass small constants (0 = rightmost, next to the clock).
enum StatusItemRescuer {

    static func recreate(
        _ item: NSStatusItem,
        autosaveName: String,
        length: CGFloat,
        preferredPosition: CGFloat,
        configure: (NSStatusItem) -> Void
    ) -> NSStatusItem {
        NSStatusBar.system.removeStatusItem(item)
        UserDefaults.standard.set(
            preferredPosition,
            forKey: "NSStatusItem Preferred Position \(autosaveName)"
        )
        let fresh = NSStatusBar.system.statusItem(withLength: length)
        fresh.autosaveName = autosaveName
        configure(fresh)
        return fresh
    }
}
