import CoreGraphics
import Foundation

/// The side of Pelmet's divider where an item belongs.
public enum ProfileItemSide: String, Codable, CaseIterable, Equatable {
    case managed
    case alwaysVisible

    public var label: String {
        switch self {
        case .managed: return "Hidden by Pelmet"
        case .alwaysVisible: return "Always visible"
        }
    }
}

/// A persisted identity for a menu bar item.
///
/// Process IDs and frames are deliberately absent: both change during normal
/// launches and layout reflows. An Accessibility title is the strongest
/// discriminator when one exists. Titleless items use an occurrence within the
/// owning application as a bounded fallback.
public struct ProfileItemKey: Codable, Hashable, Equatable {
    public let bundleIdentifier: String
    public let accessibilityTitle: String?
    public let occurrence: Int?

    public init(
        bundleIdentifier: String,
        accessibilityTitle: String? = nil,
        occurrence: Int? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.accessibilityTitle = accessibilityTitle
        self.occurrence = occurrence
    }

    /// Whether this saved key can refer to the candidate. A missing saved
    /// title is a deliberate fallback, not a wildcard for another bundle.
    public func matches(_ candidate: ProfileItemKey) -> Bool {
        guard bundleIdentifier == candidate.bundleIdentifier else { return false }
        if let accessibilityTitle {
            guard accessibilityTitle == candidate.accessibilityTitle else { return false }
        }
        if let occurrence {
            guard occurrence == candidate.occurrence else { return false }
        }
        return true
    }

    public var stableDescription: String {
        var parts = [bundleIdentifier]
        if let accessibilityTitle, !accessibilityTitle.isEmpty {
            parts.append(accessibilityTitle)
        }
        if let occurrence {
            parts.append("#\(occurrence + 1)")
        }
        return parts.joined(separator: " · ")
    }
}

/// One item and its desired side/order in a saved profile.
public struct ProfileItemPlacement: Codable, Equatable, Identifiable {
    public let key: ProfileItemKey
    public var displayName: String
    public var side: ProfileItemSide
    /// Left-to-right order in the menu bar, starting at zero.
    public var order: Int

    public init(
        key: ProfileItemKey,
        displayName: String,
        side: ProfileItemSide,
        order: Int
    ) {
        self.key = key
        self.displayName = displayName
        self.side = side
        self.order = order
    }

    public var id: String {
        "\(key.stableDescription)|\(order)|\(displayName)"
    }
}

/// A named arrangement. Profiles intentionally contain arrangement only;
/// hover, auto-rehide, spacing, and collapse state remain global preferences.
public struct MenuBarProfile: Codable, Equatable, Identifiable {
    public let id: UUID
    public var name: String
    public var placements: [ProfileItemPlacement]
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        placements: [ProfileItemPlacement],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.placements = placements.sorted { lhs, rhs in
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        self.createdAt = createdAt
    }
}

/// A currently observed item prepared for profile matching.
public struct ProfileItemCandidate: Equatable {
    public let key: ProfileItemKey
    public let displayName: String
    public let side: ProfileItemSide
    public let order: Int
    public let frame: CGRect

    public init(
        key: ProfileItemKey,
        displayName: String,
        side: ProfileItemSide,
        order: Int,
        frame: CGRect = .zero
    ) {
        self.key = key
        self.displayName = displayName
        self.side = side
        self.order = order
        self.frame = frame
    }
}

/// A unique saved-to-current item pairing.
public struct ProfileItemMatch: Equatable {
    public let placement: ProfileItemPlacement
    public let candidate: ProfileItemCandidate

    public init(placement: ProfileItemPlacement, candidate: ProfileItemCandidate) {
        self.placement = placement
        self.candidate = candidate
    }
}

/// Deterministic result of matching a saved profile against the current bar.
public struct ProfileMatchResult: Equatable {
    public let matches: [ProfileItemMatch]
    public let missing: [ProfileItemPlacement]
    public let ambiguous: [ProfileItemPlacement]

    public init(
        matches: [ProfileItemMatch],
        missing: [ProfileItemPlacement],
        ambiguous: [ProfileItemPlacement]
    ) {
        self.matches = matches
        self.missing = missing
        self.ambiguous = ambiguous
    }
}

/// Matches saved identities without guessing when a fallback identity is not
/// unique. A unique title match can survive a same-app reorder; occurrence is
/// used to disambiguate an exact duplicate title when it is still available.
/// An ambiguous placement is reported and its candidate is not consumed by
/// another placement.
public enum ProfileMatcher {

    public static func match(
        profile: MenuBarProfile,
        candidates: [ProfileItemCandidate]
    ) -> ProfileMatchResult {
        let placements = profile.placements.sorted { lhs, rhs in
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        var usedCandidateIndexes = Set<Int>()
        var matches: [ProfileItemMatch] = []
        var missing: [ProfileItemPlacement] = []
        var ambiguous: [ProfileItemPlacement] = []

        for placement in placements {
            let exact = candidates.indices.filter { index in
                !usedCandidateIndexes.contains(index)
                    && placement.key.matches(candidates[index].key)
            }
            let possible: [Int]
            if !exact.isEmpty {
                possible = exact
            } else if let title = placement.key.accessibilityTitle {
                possible = candidates.indices.filter { index in
                    !usedCandidateIndexes.contains(index)
                        && candidates[index].key.bundleIdentifier == placement.key.bundleIdentifier
                        && candidates[index].key.accessibilityTitle == title
                }
            } else {
                possible = []
            }
            switch possible.count {
            case 0:
                missing.append(placement)
            case 1:
                let index = possible[0]
                usedCandidateIndexes.insert(index)
                matches.append(ProfileItemMatch(
                    placement: placement,
                    candidate: candidates[index]
                ))
            default:
                ambiguous.append(placement)
            }
        }

        return ProfileMatchResult(matches: matches, missing: missing, ambiguous: ambiguous)
    }
}

/// User-facing summary of a profile application. The AppKit coordinator
/// fills this after each safe drag attempt; the pure matcher supplies the
/// missing and ambiguous lists.
public struct ProfileApplyResult: Codable, Equatable {
    public let profileID: UUID
    public let profileName: String
    public let appliedCount: Int
    public let skippedCount: Int
    public let missing: [ProfileItemPlacement]
    public let ambiguous: [ProfileItemPlacement]
    public let permissionRequired: Bool
    public let failed: Bool

    public init(
        profileID: UUID,
        profileName: String,
        appliedCount: Int,
        skippedCount: Int,
        missing: [ProfileItemPlacement] = [],
        ambiguous: [ProfileItemPlacement] = [],
        permissionRequired: Bool = false,
        failed: Bool = false
    ) {
        self.profileID = profileID
        self.profileName = profileName
        self.appliedCount = appliedCount
        self.skippedCount = skippedCount
        self.missing = missing
        self.ambiguous = ambiguous
        self.permissionRequired = permissionRequired
        self.failed = failed
    }

    public var isComplete: Bool {
        !failed && !permissionRequired && skippedCount == 0
            && missing.isEmpty && ambiguous.isEmpty
    }

    public var summary: String {
        if permissionRequired {
            return "Accessibility permission is required to move menu bar icons."
        }
        if failed, appliedCount == 0, skippedCount == 0, missing.isEmpty, ambiguous.isEmpty {
            return "The profile could not be applied completely."
        }
        if appliedCount == 0, skippedCount == 0, missing.isEmpty, ambiguous.isEmpty {
            return "Profile already matches the current arrangement."
        }
        var text = "Applied \(appliedCount) item\(appliedCount == 1 ? "" : "s")"
        let unresolved = missing.count + ambiguous.count + skippedCount
        if unresolved > 0 {
            text += "; left \(unresolved) item\(unresolved == 1 ? "" : "s") unchanged"
        }
        return text + (failed ? ". Some moves could not be confirmed." : ".")
    }
}
