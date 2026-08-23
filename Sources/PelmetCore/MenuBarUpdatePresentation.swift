/// Update-specific text that is combined with Pelmet's existing menu-bar
/// chevron, notch count, tooltip, and accessibility value.
public struct MenuBarUpdatePresentation: Equatable, Sendable {
    public let badgeText: String
    /// Space-constrained form drawn above the fixed-width state chevron.
    public let compactBadgeText: String
    public let actionTitle: String
    public let tooltipNotice: String?
    public let accessibilityNotice: String?

    public init(
        swallowedCount: Int,
        showsSwallowedCount: Bool,
        availableVersion: String?
    ) {
        let countText = showsSwallowedCount && swallowedCount > 0
            ? "+\(swallowedCount)"
            : nil
        let compactCountText: String?
        if showsSwallowedCount && swallowedCount > 0 {
            compactCountText = swallowedCount > 99 ? "99+" : "+\(swallowedCount)"
        } else {
            compactCountText = nil
        }
        let updateText = availableVersion == nil ? nil : "↑"
        badgeText = [countText, updateText].compactMap { $0 }.joined(separator: " ")
        compactBadgeText = [compactCountText, updateText].compactMap { $0 }.joined()

        if let availableVersion {
            actionTitle = "Update Pelmet to \(availableVersion)…"
            tooltipNotice = "Pelmet \(availableVersion) is available. Right-click to update."
            accessibilityNotice = "Update \(availableVersion) available. Right-click to update."
        } else {
            actionTitle = "Check for Updates…"
            tooltipNotice = nil
            accessibilityNotice = nil
        }
    }
}
