import Testing
@testable import PelmetCore

struct SemanticVersionTests {

    @Test func testParsesStablePrereleaseAndBuildMetadata() {
        #expect(SemanticVersion("1.2.3")?.description == "1.2.3")
        #expect(SemanticVersion("1.2.3-beta.2+build.19")?.description == "1.2.3-beta.2")
    }

    @Test func testRejectsInvalidVersions() {
        for value in ["", "1", "1.2", "01.2.3", "1.02.3", "1.2.03", "1.2.3-", "1.2.3-01"] {
            #expect(SemanticVersion(value) == nil)
        }
    }

    @Test func testSemanticVersionPrecedence() throws {
        let ordered = [
            "1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta",
            "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0",
        ].compactMap(SemanticVersion.init)

        #expect(ordered.count == 8)
        for pair in zip(ordered, ordered.dropFirst()) {
            #expect(pair.0 < pair.1)
        }
    }

    @Test func testBuildMetadataDoesNotAffectEquality() throws {
        #expect(SemanticVersion("1.2.3+one") == SemanticVersion("1.2.3+two"))
    }
}
