/// One-Click Access must remain manageable after the obstruction that made it
/// relevant disappears. Otherwise an enabled Accessibility-backed engine can
/// persist while its only in-app off switch is hidden.
public enum OneClickAccessPanePolicy {

    public static func isAvailable(
        hasMenuBarObstruction: Bool,
        isEnabled: Bool
    ) -> Bool {
        hasMenuBarObstruction || isEnabled
    }
}
