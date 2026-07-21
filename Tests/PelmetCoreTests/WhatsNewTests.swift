import Testing
@testable import PelmetCore

struct WhatsNewTests {

    private let markdown = """
    # Changelog

    ## [Unreleased]

    ### Added

    - Not ready yet.

    ## [0.3.0] - 2026-07-19

    ### Added

    - **Shelf improvements** with `inline code` and a
      continuation line.

    ### Fixed

    - Fixed a crash.

    ## [0.2.0] - 2026-07-13

    ### Changed

    - Added [Sparkle](https://sparkle-project.org).

    [Unreleased]: https://example.com/compare
    [0.3.0]: https://example.com/0.3.0
    """

    @Test func testParsesVersionedSectionsAndMultilineBullets() throws {
        let releases = ChangelogParser.parse(markdown)

        #expect(releases.count == 2)
        #expect(releases[0].version == SemanticVersion("0.3.0"))
        #expect(releases[0].date == "2026-07-19")
        #expect(releases[0].sections.map(\.title) == ["Added", "Fixed"])
        #expect(releases[0].sections[0].items == [
            "**Shelf improvements** with `inline code` and a continuation line."
        ])
        #expect(releases[1].sections[0].items[0].contains("[Sparkle](https://sparkle-project.org)"))
    }

    @Test func testIgnoresMalformedAndUnreleasedHeadings() {
        let releases = ChangelogParser.parse("""
        ## [Unreleased]
        ### Added
        - No.
        ## [01.2.3] - 2026-01-01
        ### Fixed
        - Invalid SemVer.
        """)

        #expect(releases.isEmpty)
    }

    @Test func testFreshInstallEstablishesBaseline() {
        let decision = WhatsNewPolicy.decision(
            currentVersion: "0.3.0",
            lastAcknowledgedVersion: nil,
            hadExistingPreferences: false,
            releases: ChangelogParser.parse(markdown)
        )
        #expect(decision == .establishBaseline(version: SemanticVersion("0.3.0")!))
    }

    @Test func testFirstRolloutShowsOnlyCurrentReleaseToExistingInstall() {
        let decision = WhatsNewPolicy.decision(
            currentVersion: "0.3.0",
            lastAcknowledgedVersion: nil,
            hadExistingPreferences: true,
            releases: ChangelogParser.parse(markdown)
        )
        guard case let .present(content) = decision else {
            Issue.record("Expected release notes")
            return
        }
        #expect(content.releases.map(\.version) == [SemanticVersion("0.3.0")!])
    }

    @Test func testSkippedUpgradeShowsAllUnseenVersionsNewestFirst() {
        let decision = WhatsNewPolicy.decision(
            currentVersion: "0.3.0",
            lastAcknowledgedVersion: "0.1.0",
            hadExistingPreferences: true,
            releases: ChangelogParser.parse(markdown)
        )
        guard case let .present(content) = decision else {
            Issue.record("Expected release notes")
            return
        }
        #expect(content.releases.map(\.version) == [
            SemanticVersion("0.3.0")!, SemanticVersion("0.2.0")!,
        ])
    }

    @Test func testSameVersionAndDowngradeDoNothing() {
        let releases = ChangelogParser.parse(markdown)
        #expect(WhatsNewPolicy.decision(
            currentVersion: "0.3.0", lastAcknowledgedVersion: "0.3.0",
            hadExistingPreferences: true, releases: releases
        ) == .none)
        #expect(WhatsNewPolicy.decision(
            currentVersion: "0.2.0", lastAcknowledgedVersion: "0.3.0",
            hadExistingPreferences: true, releases: releases
        ) == .none)
    }

    @Test func testDevelopmentAndInvalidVersionsDoNothing() {
        #expect(WhatsNewPolicy.decision(
            currentVersion: nil, lastAcknowledgedVersion: nil,
            hadExistingPreferences: true, releases: []
        ) == .none)
        #expect(WhatsNewPolicy.decision(
            currentVersion: "Development build", lastAcknowledgedVersion: nil,
            hadExistingPreferences: true, releases: []
        ) == .none)
    }

    @Test func testMissingReleaseStillPresentsFallbackContent() {
        let decision = WhatsNewPolicy.decision(
            currentVersion: "0.4.0",
            lastAcknowledgedVersion: "0.3.0",
            hadExistingPreferences: true,
            releases: ChangelogParser.parse(markdown)
        )
        guard case let .present(content) = decision else {
            Issue.record("Expected fallback content")
            return
        }
        #expect(content.currentVersion == SemanticVersion("0.4.0"))
        #expect(content.releases.isEmpty)
    }

    @Test func testAcknowledgmentRequiresSuccessfulOpenThenDismissal() {
        var session = WhatsNewAcknowledgmentSession(version: SemanticVersion("0.4.0")!)

        #expect(session.recordDismissal() == nil)
        session.recordSuccessfulOpen()
        #expect(session.recordDismissal() == SemanticVersion("0.4.0"))
        #expect(session.recordDismissal() == nil)
    }
}
