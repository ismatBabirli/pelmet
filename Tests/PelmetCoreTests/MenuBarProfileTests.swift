import Foundation
import PelmetCore
import Testing

struct MenuBarProfileTests {

    private let vpnKey = ProfileItemKey(
        bundleIdentifier: "com.example.vpn",
        accessibilityTitle: "VPN",
        occurrence: nil
    )

    @Test func profileRoundTripsThroughCodable() throws {
        let profile = MenuBarProfile(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            name: "Work",
            placements: [
                ProfileItemPlacement(
                    key: vpnKey,
                    displayName: "VPN",
                    side: .alwaysVisible,
                    order: 1
                ),
            ],
            createdAt: Date(timeIntervalSince1970: 123)
        )

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(MenuBarProfile.self, from: data)

        #expect(decoded == profile)
        #expect(decoded.placements.map(\.order) == [1])
    }

    @Test func titleAndBundleMustMatch() {
        let candidate = ProfileItemKey(
            bundleIdentifier: "com.example.other",
            accessibilityTitle: "VPN"
        )

        #expect(!vpnKey.matches(candidate))
        #expect(vpnKey.matches(vpnKey))
        let occurrenceKey = ProfileItemKey(
            bundleIdentifier: "com.example.vpn",
            accessibilityTitle: "VPN",
            occurrence: 1
        )
        #expect(occurrenceKey.matches(ProfileItemKey(
            bundleIdentifier: "com.example.vpn",
            accessibilityTitle: "VPN",
            occurrence: 2
        )) == false)
    }

    @Test func titlelessKeyUsesOccurrenceAsFallback() {
        let saved = ProfileItemKey(
            bundleIdentifier: "com.example.tool",
            occurrence: 1
        )
        let sameOccurrence = ProfileItemKey(
            bundleIdentifier: "com.example.tool",
            accessibilityTitle: "",
            occurrence: 1
        )
        let differentOccurrence = ProfileItemKey(
            bundleIdentifier: "com.example.tool",
            occurrence: 0
        )

        #expect(saved.matches(sameOccurrence))
        #expect(!saved.matches(differentOccurrence))
    }

    @Test func matcherReportsMissingAndMatchesKnownItems() {
        let profile = MenuBarProfile(
            name: "Work",
            placements: [
                ProfileItemPlacement(key: vpnKey, displayName: "VPN", side: .alwaysVisible, order: 0),
                ProfileItemPlacement(
                    key: ProfileItemKey(bundleIdentifier: "com.example.chat"),
                    displayName: "Chat",
                    side: .managed,
                    order: 1
                ),
            ]
        )
        let candidates = [
            ProfileItemCandidate(
                key: vpnKey,
                displayName: "VPN",
                side: .managed,
                order: 0
            ),
        ]

        let result = ProfileMatcher.match(profile: profile, candidates: candidates)

        #expect(result.matches.count == 1)
        #expect(result.matches[0].placement.displayName == "VPN")
        #expect(result.missing.map(\.displayName) == ["Chat"])
        #expect(result.ambiguous.isEmpty)
    }

    @Test func uniqueTitleMatchSurvivesSameAppReorder() {
        let profile = MenuBarProfile(
            name: "Work",
            placements: [
                ProfileItemPlacement(
                    key: ProfileItemKey(
                        bundleIdentifier: "com.example.tool",
                        accessibilityTitle: "VPN",
                        occurrence: 0
                    ),
                    displayName: "VPN",
                    side: .managed,
                    order: 0
                ),
            ]
        )
        let candidate = ProfileItemCandidate(
            key: ProfileItemKey(
                bundleIdentifier: "com.example.tool",
                accessibilityTitle: "VPN",
                occurrence: 1
            ),
            displayName: "VPN",
            side: .managed,
            order: 0
        )

        let result = ProfileMatcher.match(profile: profile, candidates: [candidate])

        #expect(result.matches.count == 1)
        #expect(result.missing.isEmpty)
        #expect(result.ambiguous.isEmpty)
    }

    @Test func matcherLeavesDuplicateFallbacksAmbiguous() {
        let profile = MenuBarProfile(
            name: "Travel",
            placements: [
                ProfileItemPlacement(
                    key: ProfileItemKey(bundleIdentifier: "com.example.tool"),
                    displayName: "Tool",
                    side: .managed,
                    order: 0
                ),
            ]
        )
        let candidates = [
            ProfileItemCandidate(
                key: ProfileItemKey(bundleIdentifier: "com.example.tool", accessibilityTitle: "One"),
                displayName: "Tool",
                side: .managed,
                order: 0
            ),
            ProfileItemCandidate(
                key: ProfileItemKey(bundleIdentifier: "com.example.tool", accessibilityTitle: "Two"),
                displayName: "Tool",
                side: .alwaysVisible,
                order: 1
            ),
        ]

        let result = ProfileMatcher.match(profile: profile, candidates: candidates)

        #expect(result.matches.isEmpty)
        #expect(result.missing.isEmpty)
        #expect(result.ambiguous.count == 1)
    }

    @Test func applyResultSummarizesBestEffortOutcome() {
        let result = ProfileApplyResult(
            profileID: UUID(),
            profileName: "Presentation",
            appliedCount: 2,
            skippedCount: 1,
            missing: [
                ProfileItemPlacement(key: vpnKey, displayName: "VPN", side: .managed, order: 0),
            ]
        )

        #expect(result.summary == "Applied 2 items; left 2 items unchanged.")
        #expect(!result.isComplete)
        #expect(!ProfileApplyResult(
            profileID: UUID(),
            profileName: "Travel",
            appliedCount: 1,
            skippedCount: 1
        ).isComplete)
    }

    @Test func applyResultRoundTripsThroughCodable() throws {
        let result = ProfileApplyResult(
            profileID: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            profileName: "Travel",
            appliedCount: 1,
            skippedCount: 2,
            ambiguous: [
                ProfileItemPlacement(
                    key: ProfileItemKey(bundleIdentifier: "com.example.tool"),
                    displayName: "Tool",
                    side: .managed,
                    order: 0
                ),
            ],
            permissionRequired: false,
            failed: true
        )

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ProfileApplyResult.self, from: data)

        #expect(decoded == result)
    }
}
