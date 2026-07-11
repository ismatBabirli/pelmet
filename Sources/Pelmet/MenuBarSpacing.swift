import CoreFoundation
import Foundation

/// The system-wide menu bar density knobs. macOS spaces status items with
/// NSStatusItemSpacing / NSStatusItemSelectionPadding, stored per-host in
/// the global domain (the `defaults -currentHost write -globalDomain` pair
/// users trade as a notch workaround; Bartender 6 productized the same
/// tweak). Writing them needs no permission, but macOS reads them at login —
/// changes take effect the next time the user logs in.
enum MenuBarSpacing {

    enum Profile: String, CaseIterable, Identifiable {
        case systemDefault
        case reduced
        case compact

        var id: String { rawValue }

        /// (spacing, selectionPadding); nil = remove the override.
        var values: (spacing: Int, padding: Int)? {
            switch self {
            case .systemDefault: return nil
            case .reduced: return (12, 8)
            case .compact: return (8, 8)
            }
        }

        var label: String {
            switch self {
            case .systemDefault: return "System default"
            case .reduced: return "Reduced — subtle change"
            case .compact: return "Compact — fits the most icons"
            }
        }
    }

    private static let spacingKey = "NSStatusItemSpacing" as CFString
    private static let paddingKey = "NSStatusItemSelectionPadding" as CFString

    /// What is currently written (not necessarily active until next login).
    static func currentProfile() -> Profile {
        let spacing = readValue(spacingKey)
        let padding = readValue(paddingKey)
        switch (spacing, padding) {
        case (nil, nil): return .systemDefault
        case (12, 8): return .reduced
        case (8, 8): return .compact
        default: return .systemDefault // custom values set outside Pelmet — don't claim them
        }
    }

    static func hasCustomValuesOutsidePelmet() -> Bool {
        let spacing = readValue(spacingKey)
        let padding = readValue(paddingKey)
        if spacing == nil && padding == nil { return false }
        return !((spacing == 12 && padding == 8) || (spacing == 8 && padding == 8))
    }

    static func apply(_ profile: Profile) {
        if let values = profile.values {
            write(spacingKey, values.spacing)
            write(paddingKey, values.padding)
        } else {
            write(spacingKey, nil)
            write(paddingKey, nil)
        }
        CFPreferencesSynchronize(
            kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost
        )
    }

    private static func readValue(_ key: CFString) -> Int? {
        CFPreferencesCopyValue(
            key, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost
        ) as? Int
    }

    private static func write(_ key: CFString, _ value: Int?) {
        CFPreferencesSetValue(
            key,
            value.map { $0 as CFNumber },
            kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost
        )
    }
}
