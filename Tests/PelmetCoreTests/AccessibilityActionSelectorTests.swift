import Testing
@testable import PelmetCore

struct AccessibilityActionSelectorTests {

    @Test func showMenuIsPreferredOverPress() {
        let action = AccessibilityActionSelector.preferred(
            from: ["AXPress", "AXShowMenu"]
        )
        #expect(action == .showMenu)
    }

    @Test func pressIsUsedWhenShowMenuIsUnavailable() {
        let action = AccessibilityActionSelector.preferred(from: ["AXPress"])
        #expect(action == .press)
    }

    @Test func unrelatedActionsAreRejected() {
        let action = AccessibilityActionSelector.preferred(
            from: ["AXRaise", "AXConfirm"]
        )
        #expect(action == nil)
    }

    @Test func emptyActionListIsRejected() {
        #expect(AccessibilityActionSelector.preferred(from: []) == nil)
    }
}
