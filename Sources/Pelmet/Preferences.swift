import Foundation

/// Simple UserDefaults-backed preferences.
/// Kept as static accessors so both AppKit (MenuBarManager)
/// and SwiftUI (@AppStorage in the Settings panes) read the same keys.
enum Preferences {

    enum Keys {
        static let autoRehide = "autoRehide"
        static let rehideDelay = "rehideDelay"
        static let isCollapsed = "isCollapsed"
        static let showSwallowedCount = "showSwallowedCount"
        static let didShowDividerTip = "didShowDividerTip"
        static let didShowToggleTip = "didShowToggleTip"
        static let didShowSwallowedEducation = "didShowSwallowedEducation"
        static let hasEverManagedItems = "hasEverManagedItems"
        static let shelfEnabled = "shelfEnabled"
        static let didShowShelfTip = "didShowShelfTip"
        static let activationEngineEnabled = "activationEngineEnabled"
        static let didPromptForAccessibility = "didPromptForAccessibility"
        static let didOfferOneClick = "didOfferOneClick"
        static let didAutoPromptAccessibility = "didAutoPromptAccessibility"
        static let awaitingOneClickGrant = "awaitingOneClickGrant"
        static let settingsPane = "settingsPane"
    }

    /// Last collapse state, restored at launch. Defaults to expanded so a
    /// first-time user actually sees the ╱ divider they drag icons against.
    static var isCollapsed: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.isCollapsed) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.isCollapsed) }
    }

    static var autoRehide: Bool {
        UserDefaults.standard.object(forKey: Keys.autoRehide) as? Bool ?? true
    }

    /// Seconds before revealed items hide again.
    static var rehideDelay: TimeInterval {
        let value = UserDefaults.standard.double(forKey: Keys.rehideDelay)
        return value > 0 ? value : 10
    }

    /// Show the "+N icons don't fit" count on the chevron. The right-click
    /// menu reports the situation either way.
    static var showSwallowedCount: Bool {
        UserDefaults.standard.object(forKey: Keys.showSwallowedCount) as? Bool ?? true
    }

    /// Clicking the chevron while it shows "+N" opens the Shelf (the panel
    /// listing icons the notch hid) instead of collapsing. The right-click
    /// menu and ⌥⌘N open the Shelf regardless of this setting.
    static var shelfEnabled: Bool {
        UserDefaults.standard.object(forKey: Keys.shelfEnabled) as? Bool ?? true
    }

    /// Opt-in for the Accessibility-gated activation engine (one-click
    /// opening of hidden items). Strictly off by default: the zero-permission
    /// core is sacred.
    static var activationEngineEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.activationEngineEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.activationEngineEnabled) }
    }

    /// Last-selected Settings pane (`SettingsPane.rawValue`); General when
    /// unset or no longer available (e.g. a stale One-Click Access selection
    /// on a non-notched Mac).
    static var settingsPane: String {
        get { UserDefaults.standard.string(forKey: Keys.settingsPane) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.settingsPane) }
    }

    /// Whether the system Accessibility prompt was ever triggered — needed to
    /// tell "never asked" apart from "asked and declined" (TCC exposes no
    /// notDetermined/denied distinction to the app).
    static var didPromptForAccessibility: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.didPromptForAccessibility) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.didPromptForAccessibility) }
    }

    /// One-shot gate for the first-run "one-click access" pitch popover. Reset
    /// by `resetOnboardingFlags()` so "Show Welcome Tips Again" re-offers it.
    static var didOfferOneClick: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.didOfferOneClick) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.didOfferOneClick) }
    }

    /// Ensures the system Accessibility prompt is auto-fired at most once ever
    /// (first run only). Never reset — a replay re-offers the pitch but must
    /// not auto-fire the OS dialog again.
    static var didAutoPromptAccessibility: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.didAutoPromptAccessibility) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.didAutoPromptAccessibility) }
    }

    /// Armed when we ask for Accessibility on the user's behalf; when the grant
    /// lands the engine turns itself on. Persisted so a grant made after the
    /// poll window (or on a later launch) still enables one-click.
    static var awaitingOneClickGrant: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.awaitingOneClickGrant) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.awaitingOneClickGrant) }
    }

    // MARK: - One-time onboarding flags

    static var didShowDividerTip: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.didShowDividerTip) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.didShowDividerTip) }
    }

    static var didShowToggleTip: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.didShowToggleTip) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.didShowToggleTip) }
    }

    static var didShowSwallowedEducation: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.didShowSwallowedEducation) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.didShowSwallowedEducation) }
    }

    static var didShowShelfTip: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.didShowShelfTip) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.didShowShelfTip) }
    }

    /// Set the first time a collapse actually hides icons — used to tell a
    /// brand-new user apart from someone who already uses the divider.
    static var hasEverManagedItems: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.hasEverManagedItems) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.hasEverManagedItems) }
    }

    static func resetOnboardingFlags() {
        didShowDividerTip = false
        didShowToggleTip = false
        didShowSwallowedEducation = false
        didShowShelfTip = false
        didOfferOneClick = false
        // NOTE: didAutoPromptAccessibility, awaitingOneClickGrant,
        // didPromptForAccessibility and activationEngineEnabled are system /
        // opt-in facts, not onboarding — never reset here.
    }
}
