import CoreGraphics
import Testing
@testable import PelmetCore

struct SoftwareIslandTests {
    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    private func observation(
        frame: CGRect = CGRect(x: 620, y: 500, width: 680, height: 580),
        layer: Int = 27,
        bundleIdentifier: String = "app.vibeisland.macos",
        isAccessoryApplication: Bool = true,
        isSystemOwner: Bool = false
    ) -> SoftwareIslandWindowObservation {
        SoftwareIslandWindowObservation(
            frame: frame,
            layer: layer,
            bundleIdentifier: bundleIdentifier,
            isAccessoryApplication: isAccessoryApplication,
            isSystemOwner: isSystemOwner
        )
    }

    @Test func registryRecognizesVibeIsland() {
        let provider = SoftwareIslandRegistry.provider(for: "app.vibeisland.macos")
        #expect(provider?.displayName == "Vibe Island")
        #expect(provider?.defaultRestingWidth == 340)
    }

    @Test func registryLeavesUnknownAppsUnmatched() {
        #expect(SoftwareIslandRegistry.provider(for: "example.unknown") == nil)
    }

    @Test func topCenteredAccessoryWindowIsCandidate() {
        #expect(SoftwareIslandCandidateClassifier.isCandidate(
            observation(), screenFrame: screen, menuBarHeight: 30
        ))
    }

    @Test func systemAndOrdinaryAppsAreRejected() {
        #expect(!SoftwareIslandCandidateClassifier.isCandidate(
            observation(isAccessoryApplication: false), screenFrame: screen, menuBarHeight: 30
        ))
        #expect(!SoftwareIslandCandidateClassifier.isCandidate(
            observation(isSystemOwner: true), screenFrame: screen, menuBarHeight: 30
        ))
    }

    @Test func statusLevelAndOffCenterWindowsAreRejected() {
        #expect(!SoftwareIslandCandidateClassifier.isCandidate(
            observation(layer: 25), screenFrame: screen, menuBarHeight: 30
        ))
        #expect(!SoftwareIslandCandidateClassifier.isCandidate(
            observation(frame: CGRect(x: 100, y: 500, width: 680, height: 580)),
            screenFrame: screen,
            menuBarHeight: 30
        ))
    }

    @Test func knownProviderCanUseAWideTransparentEnvelope() {
        let wideVibeWindow = observation(
            frame: CGRect(x: 100, y: 500, width: 1720, height: 580)
        )
        #expect(SoftwareIslandCandidateClassifier.isCandidate(
            wideVibeWindow, screenFrame: screen, menuBarHeight: 30
        ))

        let unknownWideWindow = observation(
            frame: CGRect(x: 100, y: 500, width: 1720, height: 580),
            bundleIdentifier: "example.unknown"
        )
        #expect(!SoftwareIslandCandidateClassifier.isCandidate(
            unknownWideWindow, screenFrame: screen, menuBarHeight: 30
        ))
    }

    @Test func restingRectUsesStableCalibratedWidth() {
        let rect = SoftwareIslandCandidateClassifier.restingRect(
            width: 340, screenFrame: screen, menuBarHeight: 30
        )
        #expect(rect == CGRect(x: 790, y: 1050, width: 340, height: 30))
    }

    @Test func restingRectClampsTooNarrowValues() {
        let rect = SoftwareIslandCandidateClassifier.restingRect(
            width: 20, screenFrame: screen, menuBarHeight: 30
        )
        #expect(rect.width == SoftwareIslandCandidateClassifier.minimumWidth)
        #expect(rect.midX == screen.midX)
    }

    @Test func groupingPreservesEveryScreenForOneApp() {
        let secondScreen = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        let detections = [
            SoftwareIslandDetection(
                bundleIdentifier: "app.vibeisland.macos",
                displayName: "Vibe Island",
                screenFrame: screen,
                outerWindowFrame: CGRect(x: 620, y: 500, width: 680, height: 580)
            ),
            SoftwareIslandDetection(
                bundleIdentifier: "app.vibeisland.macos",
                displayName: "Vibe Island",
                screenFrame: secondScreen,
                outerWindowFrame: CGRect(x: 2500, y: 480, width: 760, height: 600)
            ),
        ]

        let groups = SoftwareIslandDetectionGrouper.group(detections)

        #expect(groups.count == 1)
        #expect(groups[0].screenFrames == [screen, secondScreen])
        #expect(groups[0].widestOuterWindowFrame.width == 760)
    }

    @Test func groupingKeepsDifferentAppsSeparateAndDeterministic() {
        let detections = [
            SoftwareIslandDetection(
                bundleIdentifier: "z.example.island",
                displayName: "Z Island",
                screenFrame: screen,
                outerWindowFrame: CGRect(x: 700, y: 500, width: 520, height: 580)
            ),
            SoftwareIslandDetection(
                bundleIdentifier: "a.example.island",
                displayName: "A Island",
                screenFrame: screen,
                outerWindowFrame: CGRect(x: 760, y: 500, width: 400, height: 580)
            ),
        ]

        let groups = SoftwareIslandDetectionGrouper.group(detections)

        #expect(groups.map(\.bundleIdentifier) == ["a.example.island", "z.example.island"])
    }

}
