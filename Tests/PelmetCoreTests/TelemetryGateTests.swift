import Testing
@testable import PelmetCore

struct TelemetryGateTests {

    /// All-clear inputs: enabled, notice shown, real release build, no env
    /// overrides. Individual tests flip one field to prove it blocks alone.
    private func clear(
        enabledPreference: Bool = true,
        noticeShown: Bool = true,
        isDevelopmentBuild: Bool = false,
        isDebugBuild: Bool = false,
        doNotTrack: String? = nil,
        disableOverride: String? = nil,
        forceOverride: String? = nil
    ) -> TelemetryGate.Inputs {
        TelemetryGate.Inputs(
            enabledPreference: enabledPreference,
            noticeShown: noticeShown,
            isDevelopmentBuild: isDevelopmentBuild,
            isDebugBuild: isDebugBuild,
            doNotTrack: doNotTrack,
            disableOverride: disableOverride,
            forceOverride: forceOverride
        )
    }

    @Test func testActiveWhenAllClear() {
        #expect(TelemetryGate.isActive(clear()))
    }

    @Test func testEachFactorBlocksAlone() {
        #expect(!TelemetryGate.isActive(clear(enabledPreference: false)))
        #expect(!TelemetryGate.isActive(clear(noticeShown: false)))
        #expect(!TelemetryGate.isActive(clear(isDevelopmentBuild: true)))
        #expect(!TelemetryGate.isActive(clear(isDebugBuild: true)))
        #expect(!TelemetryGate.isActive(clear(doNotTrack: "1")))
        #expect(!TelemetryGate.isActive(clear(disableOverride: "1")))
    }

    @Test func testDoNotTrackWins() {
        // Enabled and notice shown, but DO_NOT_TRACK overrides everything.
        #expect(!TelemetryGate.isActive(clear(doNotTrack: "true")))
        #expect(!TelemetryGate.isActive(clear(doNotTrack: "yes")))
    }

    @Test func testEnvFlagZeroOrEmptyDoesNotBlock() {
        #expect(TelemetryGate.isActive(clear(doNotTrack: "0")))
        #expect(TelemetryGate.isActive(clear(doNotTrack: "")))
        #expect(TelemetryGate.isActive(clear(doNotTrack: "   ")))
        #expect(TelemetryGate.isActive(clear(disableOverride: "0")))
    }

    @Test func testEnvFlagSetHelper() {
        #expect(TelemetryGate.envFlagSet("1"))
        #expect(TelemetryGate.envFlagSet("true"))
        #expect(!TelemetryGate.envFlagSet(nil))
        #expect(!TelemetryGate.envFlagSet(""))
        #expect(!TelemetryGate.envFlagSet("0"))
        #expect(!TelemetryGate.envFlagSet(" 0 "))
    }

    @Test func testShouldOfferNoticeOnlyBeforeNoticeShown() {
        #expect(TelemetryGate.shouldOfferNotice(clear(noticeShown: false)))
        // Already shown: never re-offer.
        #expect(!TelemetryGate.shouldOfferNotice(clear(noticeShown: true)))
    }

    @Test func testShouldNotOfferNoticeToOptedOutOrSilencedBuilds() {
        // A user who set the pref off (via defaults write) before first launch
        // must not be nagged with a notice about data we will never send.
        #expect(!TelemetryGate.shouldOfferNotice(clear(enabledPreference: false, noticeShown: false)))
        #expect(!TelemetryGate.shouldOfferNotice(clear(noticeShown: false, isDevelopmentBuild: true)))
        #expect(!TelemetryGate.shouldOfferNotice(clear(noticeShown: false, isDebugBuild: true)))
        #expect(!TelemetryGate.shouldOfferNotice(clear(noticeShown: false, doNotTrack: "1")))
    }

    @Test func testNoticeShownButDisabledStaysInactive() {
        #expect(!TelemetryGate.isActive(clear(enabledPreference: false, noticeShown: true)))
    }

    @Test func testForceOverrideUnlocksDevAndDebugAndNotice() {
        // A local `swift run` (dev + debug build, no notice shown) sends when
        // PELMET_FORCE_TELEMETRY is set.
        #expect(TelemetryGate.isActive(clear(
            noticeShown: false,
            isDevelopmentBuild: true,
            isDebugBuild: true,
            forceOverride: "1"
        )))
    }

    @Test func testForceOverrideNeverBeatsExplicitOptOut() {
        // Force yields to DO_NOT_TRACK, the disable override, and an off preference.
        #expect(!TelemetryGate.isActive(clear(isDebugBuild: true, doNotTrack: "1", forceOverride: "1")))
        #expect(!TelemetryGate.isActive(clear(isDebugBuild: true, disableOverride: "1", forceOverride: "1")))
        #expect(!TelemetryGate.isActive(clear(enabledPreference: false, isDebugBuild: true, forceOverride: "1")))
    }

    @Test func testForceOverrideUnsetOrZeroDoesNotUnlock() {
        #expect(!TelemetryGate.isActive(clear(isDebugBuild: true, forceOverride: "0")))
        #expect(!TelemetryGate.isActive(clear(isDebugBuild: true, forceOverride: nil)))
    }
}
