import Foundation

/// Simple UserDefaults-backed preferences.
/// Kept as static accessors so both AppKit (MenuBarManager)
/// and SwiftUI (@AppStorage in SettingsView) read the same keys.
enum Preferences {

    enum Keys {
        static let autoRehide = "autoRehide"
        static let rehideDelay = "rehideDelay"
    }

    static var autoRehide: Bool {
        UserDefaults.standard.object(forKey: Keys.autoRehide) as? Bool ?? true
    }

    /// Seconds before revealed items hide again.
    static var rehideDelay: TimeInterval {
        let value = UserDefaults.standard.double(forKey: Keys.rehideDelay)
        return value > 0 ? value : 10
    }
}
