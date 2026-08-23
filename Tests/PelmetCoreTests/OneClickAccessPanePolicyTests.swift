import Testing
@testable import PelmetCore

struct OneClickAccessPanePolicyTests {

    @Test func obstructionMakesThePaneAvailable() {
        #expect(OneClickAccessPanePolicy.isAvailable(
            hasMenuBarObstruction: true,
            isEnabled: false
        ))
    }

    @Test func enabledEngineKeepsThePaneAvailableAfterTheObstructionExits() {
        #expect(OneClickAccessPanePolicy.isAvailable(
            hasMenuBarObstruction: false,
            isEnabled: true
        ))
    }

    @Test func irrelevantDisabledPaneStaysHidden() {
        #expect(!OneClickAccessPanePolicy.isAvailable(
            hasMenuBarObstruction: false,
            isEnabled: false
        ))
    }
}
