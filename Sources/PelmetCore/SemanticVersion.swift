import Foundation

/// A strict Semantic Version 2.0 value used to decide whether release notes
/// belong to a newer app version. Build metadata is accepted but deliberately
/// omitted from equality and ordering because SemVer says it has no precedence.
public struct SemanticVersion: Comparable, Hashable, Sendable, CustomStringConvertible {

    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prereleaseIdentifiers: [String]

    public init?(_ rawValue: String) {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        let buildParts = value.split(separator: "+", omittingEmptySubsequences: false)
        guard buildParts.count <= 2 else { return nil }
        if buildParts.count == 2 {
            guard Self.identifiersAreValid(String(buildParts[1]), forbidLeadingZeroes: false) else {
                return nil
            }
        }

        let precedenceParts = buildParts[0].split(
            separator: "-", maxSplits: 1, omittingEmptySubsequences: false
        )
        let numberParts = precedenceParts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard numberParts.count == 3,
              let major = Self.parseCoreNumber(numberParts[0]),
              let minor = Self.parseCoreNumber(numberParts[1]),
              let patch = Self.parseCoreNumber(numberParts[2])
        else { return nil }

        let prerelease: [String]
        if precedenceParts.count == 2 {
            let rawPrerelease = String(precedenceParts[1])
            guard Self.identifiersAreValid(rawPrerelease, forbidLeadingZeroes: true) else {
                return nil
            }
            prerelease = rawPrerelease.split(separator: ".").map(String.init)
        } else {
            prerelease = []
        }

        self.major = major
        self.minor = minor
        self.patch = patch
        self.prereleaseIdentifiers = prerelease
    }

    public var description: String {
        let core = "\(major).\(minor).\(patch)"
        guard !prereleaseIdentifiers.isEmpty else { return core }
        return core + "-" + prereleaseIdentifiers.joined(separator: ".")
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        if lhs.prereleaseIdentifiers.isEmpty { return false }
        if rhs.prereleaseIdentifiers.isEmpty { return true }

        for (left, right) in zip(lhs.prereleaseIdentifiers, rhs.prereleaseIdentifiers) {
            if left == right { continue }
            let leftNumber = Int(left)
            let rightNumber = Int(right)
            switch (leftNumber, rightNumber) {
            case let (.some(left), .some(right)): return left < right
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return left < right
            }
        }
        return lhs.prereleaseIdentifiers.count < rhs.prereleaseIdentifiers.count
    }

    private static func parseCoreNumber(_ value: Substring) -> Int? {
        guard !value.isEmpty,
              value.allSatisfy(\.isNumber),
              value == "0" || value.first != "0"
        else { return nil }
        return Int(value)
    }

    private static func identifiersAreValid(
        _ value: String,
        forbidLeadingZeroes: Bool
    ) -> Bool {
        let identifiers = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !identifiers.isEmpty else { return false }
        return identifiers.allSatisfy { identifier in
            guard !identifier.isEmpty,
                  identifier.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
            else { return false }
            if forbidLeadingZeroes,
               identifier.allSatisfy(\.isNumber),
               identifier.count > 1,
               identifier.first == "0" {
                return false
            }
            return true
        }
    }
}
