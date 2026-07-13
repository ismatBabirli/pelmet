import Testing
@testable import PelmetCore

struct AppVersionTests {

    @Test func testShortAndBuild() {
        let version = AppVersion(shortVersion: "0.2.0", build: "123")
        #expect(version.displayValue == "0.2.0 (123)")
        #expect(version.labeled() == "Pelmet 0.2.0 (123)")
        #expect(version.isDevelopmentBuild == false)
    }

    @Test func testShortOnly() {
        let version = AppVersion(shortVersion: "0.2.0", build: nil)
        #expect(version.displayValue == "0.2.0")
        #expect(version.labeled() == "Pelmet 0.2.0")
    }

    @Test func testNoShortVersionIsDevelopmentBuild() {
        let version = AppVersion(shortVersion: nil, build: nil)
        #expect(version.isDevelopmentBuild)
        #expect(version.displayValue == AppVersion.developmentBuild)
        #expect(version.labeled() == "Pelmet (Development build)")
    }

    @Test func testBuildWithoutShortStillDevelopmentBuild() {
        // A build number with no marketing version is meaningless to a user.
        let version = AppVersion(shortVersion: nil, build: "123")
        #expect(version.isDevelopmentBuild)
        #expect(version.displayValue == AppVersion.developmentBuild)
    }

    @Test func testBlankInputsNormalizeToNil() {
        let version = AppVersion(shortVersion: "  ", build: "\n")
        #expect(version.shortVersion == nil)
        #expect(version.build == nil)
        #expect(version.isDevelopmentBuild)
    }

    @Test func testCustomNameInLabel() {
        let version = AppVersion(shortVersion: "1.0.0", build: "7")
        #expect(version.labeled(name: "Pelmet Beta") == "Pelmet Beta 1.0.0 (7)")
    }
}
