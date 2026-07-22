import Testing
@testable import PelmetCore

struct MenuBarUpdatePresentationTests {
    @Test func updateOnlyPresentation() {
        let presentation = MenuBarUpdatePresentation(
            swallowedCount: 0,
            showsSwallowedCount: false,
            availableVersion: "0.4.0"
        )

        #expect(presentation.badgeText == "↑")
        #expect(presentation.actionTitle == "Update Pelmet to 0.4.0…")
        #expect(presentation.tooltipNotice == "Pelmet 0.4.0 is available. Right-click to update.")
        #expect(presentation.accessibilityNotice == "Update 0.4.0 available. Right-click to update.")
    }

    @Test func notchCountOnlyPresentation() {
        let presentation = MenuBarUpdatePresentation(
            swallowedCount: 3,
            showsSwallowedCount: true,
            availableVersion: nil
        )

        #expect(presentation.badgeText == "+3")
        #expect(presentation.actionTitle == "Check for Updates…")
        #expect(presentation.tooltipNotice == nil)
        #expect(presentation.accessibilityNotice == nil)
    }

    @Test func combinedPresentation() {
        let presentation = MenuBarUpdatePresentation(
            swallowedCount: 2,
            showsSwallowedCount: true,
            availableVersion: "1.0.0"
        )

        #expect(presentation.badgeText == "+2 ↑")
    }

    @Test func hiddenNotchCountStillShowsUpdate() {
        let presentation = MenuBarUpdatePresentation(
            swallowedCount: 4,
            showsSwallowedCount: false,
            availableVersion: "1.0.0"
        )

        #expect(presentation.badgeText == "↑")
    }
}
