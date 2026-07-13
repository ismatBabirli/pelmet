import Foundation

/// Formats the bundle's version numbers into user-facing strings, with an
/// honest fallback when they're absent. `CFBundleShortVersionString` and
/// `CFBundleVersion` are populated only in the xcodegen/xcodebuild `.app`;
/// under `swift run` there is no Info.plist, so both read back nil, the same
/// way the updater and launch-at-login degrade without a bundle. Kept here
/// (pure, no AppKit) so the formatting is unit-testable; the bundle read lives
/// in `AppVersionInfo` in the app target.
public struct AppVersion: Equatable {

    /// Shown in place of a version number when there's no marketing version:
    /// the `swift run` case.
    public static let developmentBuild = "Development build"

    /// Marketing version (`CFBundleShortVersionString`), e.g. "0.2.0".
    /// Normalized: nil when the raw value is missing or blank.
    public let shortVersion: String?
    /// Build number (`CFBundleVersion`), e.g. "123". Normalized like above.
    public let build: String?

    public init(shortVersion: String?, build: String?) {
        self.shortVersion = AppVersion.normalized(shortVersion)
        self.build = AppVersion.normalized(build)
    }

    /// True when there's no marketing version to show. A lone build number is
    /// meaningless to a user, so it keys on `shortVersion` alone.
    public var isDevelopmentBuild: Bool { shortVersion == nil }

    /// The value text without the word "Version"; pairs with
    /// `LabeledContent("Version", value:)`. "0.2.0 (123)" when both are
    /// present, "0.2.0" with no build, `developmentBuild` otherwise.
    public var displayValue: String {
        guard let shortVersion else { return AppVersion.developmentBuild }
        guard let build else { return shortVersion }
        return "\(shortVersion) (\(build))"
    }

    /// A one-line, name-prefixed label for the menu bar and the
    /// copy-for-bug-report button: "Pelmet 0.2.0 (123)", or
    /// "Pelmet (Development build)" when there's no version.
    public func labeled(name: String = "Pelmet") -> String {
        isDevelopmentBuild
            ? "\(name) (\(displayValue))"
            : "\(name) \(displayValue)"
    }

    private static func normalized(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}
