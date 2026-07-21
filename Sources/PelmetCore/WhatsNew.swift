import Foundation

public struct ChangelogSection: Equatable, Sendable {
    public let title: String
    public let items: [String]

    public init(title: String, items: [String]) {
        self.title = title
        self.items = items
    }
}

public struct ChangelogRelease: Equatable, Sendable {
    public let version: SemanticVersion
    public let date: String?
    public let sections: [ChangelogSection]

    public init(
        version: SemanticVersion,
        date: String? = nil,
        sections: [ChangelogSection]
    ) {
        self.version = version
        self.date = date
        self.sections = sections
    }
}

/// Parses the versioned sections of the repository's Keep a Changelog file.
/// Block-level Markdown is reduced to releases, section headings, and bullets;
/// inline Markdown inside a bullet is preserved for the SwiftUI renderer.
public enum ChangelogParser {

    public static func parse(_ markdown: String) -> [ChangelogRelease] {
        var releases: [ChangelogRelease] = []
        var releaseBuilder: ReleaseBuilder?
        var sectionBuilder: SectionBuilder?

        func finishSection() {
            guard let section = sectionBuilder else { return }
            sectionBuilder = nil
            guard !section.items.isEmpty else { return }
            releaseBuilder?.sections.append(
                ChangelogSection(title: section.title, items: section.items)
            )
        }

        func finishRelease() {
            finishSection()
            guard let release = releaseBuilder else { return }
            releaseBuilder = nil
            releases.append(ChangelogRelease(
                version: release.version,
                date: release.date,
                sections: release.sections
            ))
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("## ") && !trimmed.hasPrefix("### ") {
                finishRelease()
                releaseBuilder = parseReleaseHeading(trimmed)
                continue
            }

            guard releaseBuilder != nil else { continue }

            if trimmed.hasPrefix("### ") {
                finishSection()
                let title = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                if !title.isEmpty {
                    sectionBuilder = SectionBuilder(title: title, items: [])
                }
                continue
            }

            guard sectionBuilder != nil else { continue }
            if trimmed.hasPrefix("- ") {
                let item = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !item.isEmpty { sectionBuilder?.items.append(item) }
            } else if !trimmed.isEmpty,
                      !isLinkDefinition(trimmed),
                      sectionBuilder?.items.isEmpty == false {
                let last = sectionBuilder!.items.removeLast()
                sectionBuilder!.items.append(last + " " + trimmed)
            }
        }

        finishRelease()
        return releases
    }

    private static func parseReleaseHeading(_ heading: String) -> ReleaseBuilder? {
        guard heading.hasPrefix("## ["),
              let closingBracket = heading.firstIndex(of: "]")
        else { return nil }

        let versionStart = heading.index(heading.startIndex, offsetBy: 4)
        guard versionStart < closingBracket,
              let version = SemanticVersion(String(heading[versionStart..<closingBracket]))
        else { return nil }

        let remainderStart = heading.index(after: closingBracket)
        let remainder = heading[remainderStart...].trimmingCharacters(in: .whitespaces)
        let date: String?
        if remainder.hasPrefix("-") {
            let value = remainder.dropFirst().trimmingCharacters(in: .whitespaces)
            date = value.isEmpty ? nil : value
        } else {
            date = nil
        }
        return ReleaseBuilder(version: version, date: date, sections: [])
    }

    private static func isLinkDefinition(_ line: String) -> Bool {
        guard line.hasPrefix("["), let marker = line.firstIndex(of: "]") else { return false }
        let next = line.index(after: marker)
        return next < line.endIndex && line[next] == ":"
    }

    private final class ReleaseBuilder {
        let version: SemanticVersion
        let date: String?
        var sections: [ChangelogSection]

        init(version: SemanticVersion, date: String?, sections: [ChangelogSection]) {
            self.version = version
            self.date = date
            self.sections = sections
        }
    }

    private struct SectionBuilder {
        let title: String
        var items: [String]
    }
}

public struct WhatsNewContent: Equatable, Sendable {
    public let currentVersion: SemanticVersion
    public let releases: [ChangelogRelease]

    public init(currentVersion: SemanticVersion, releases: [ChangelogRelease]) {
        self.currentVersion = currentVersion
        self.releases = releases
    }
}

public enum WhatsNewDecision: Equatable, Sendable {
    case none
    case establishBaseline(version: SemanticVersion)
    case present(WhatsNewContent)
}

/// Tracks the two UI facts required before a version may be persisted as seen:
/// the window actually became visible, and it was subsequently dismissed.
public struct WhatsNewAcknowledgmentSession: Equatable, Sendable {
    public let version: SemanticVersion
    private var openedSuccessfully = false
    private var acknowledged = false

    public init(version: SemanticVersion) {
        self.version = version
    }

    public mutating func recordSuccessfulOpen() {
        openedSuccessfully = true
    }

    /// Returns the version exactly once, and only after a successful open.
    public mutating func recordDismissal() -> SemanticVersion? {
        guard openedSuccessfully, !acknowledged else { return nil }
        acknowledged = true
        return version
    }
}

/// Pure launch policy. The app layer owns UserDefaults and acknowledgment;
/// this type only decides what a launch should do from supplied facts.
public enum WhatsNewPolicy {

    public static func decision(
        currentVersion rawCurrentVersion: String?,
        lastAcknowledgedVersion rawLastAcknowledgedVersion: String?,
        hadExistingPreferences: Bool,
        releases: [ChangelogRelease]
    ) -> WhatsNewDecision {
        guard let rawCurrentVersion,
              let currentVersion = SemanticVersion(rawCurrentVersion)
        else { return .none }

        guard let rawLastAcknowledgedVersion else {
            if hadExistingPreferences {
                let currentRelease = releases.first { $0.version == currentVersion }
                return .present(WhatsNewContent(
                    currentVersion: currentVersion,
                    releases: currentRelease.map { [$0] } ?? []
                ))
            }
            return .establishBaseline(version: currentVersion)
        }

        guard let lastAcknowledgedVersion = SemanticVersion(rawLastAcknowledgedVersion) else {
            let currentRelease = releases.first { $0.version == currentVersion }
            return .present(WhatsNewContent(
                currentVersion: currentVersion,
                releases: currentRelease.map { [$0] } ?? []
            ))
        }

        guard currentVersion > lastAcknowledgedVersion else { return .none }

        let unseenReleases = releases
            .filter { $0.version > lastAcknowledgedVersion && $0.version <= currentVersion }
            .sorted { $0.version > $1.version }
        return .present(WhatsNewContent(
            currentVersion: currentVersion,
            releases: unseenReleases
        ))
    }
}
