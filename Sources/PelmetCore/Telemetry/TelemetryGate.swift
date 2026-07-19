import Foundation

/// Pure decision logic for whether telemetry may run. Every input is passed in
/// so the whole gate is unit-testable with no UserDefaults, environment, or
/// bundle reads. The app layer (`TelemetryManager`) gathers the inputs and
/// obeys the answer.
public enum TelemetryGate {

    public struct Inputs: Equatable {
        /// The user's `telemetryEnabled` preference (defaults to true, opt-out).
        public let enabledPreference: Bool
        /// Whether the first-run notice has been shown. Nothing may send until
        /// the user has been told, regardless of the opt-out default.
        public let noticeShown: Bool
        /// `swift run` (no Info.plist) has no marketing version.
        public let isDevelopmentBuild: Bool
        /// A `#if DEBUG` compile: the XcodeGen Debug `.app` has a real version
        /// so `isDevelopmentBuild` is false there, but it must still stay inert.
        public let isDebugBuild: Bool
        /// The `DO_NOT_TRACK` environment variable, if set.
        public let doNotTrack: String?
        /// The `PELMET_DISABLE_TELEMETRY` QA override, if set.
        public let disableOverride: String?
        /// The `PELMET_FORCE_TELEMETRY` developer override, if set. Unlocks the
        /// dev-build, debug-build, and notice gates so a local `swift run` can
        /// send a real heartbeat for testing. It never beats an explicit opt-out
        /// (`DO_NOT_TRACK`, `PELMET_DISABLE_TELEMETRY`, or `enabledPreference`).
        public let forceOverride: String?

        public init(
            enabledPreference: Bool,
            noticeShown: Bool,
            isDevelopmentBuild: Bool,
            isDebugBuild: Bool,
            doNotTrack: String?,
            disableOverride: String?,
            forceOverride: String? = nil
        ) {
            self.enabledPreference = enabledPreference
            self.noticeShown = noticeShown
            self.isDevelopmentBuild = isDevelopmentBuild
            self.isDebugBuild = isDebugBuild
            self.doNotTrack = doNotTrack
            self.disableOverride = disableOverride
            self.forceOverride = forceOverride
        }
    }

    /// May a heartbeat be sent right now?
    public static func isActive(_ i: Inputs) -> Bool {
        // Explicit opt-outs always win, even over the force override.
        if envFlagSet(i.doNotTrack) || envFlagSet(i.disableOverride) { return false }
        guard i.enabledPreference else { return false }
        // Developer/QA hatch: send from a dev or debug build without the notice.
        if envFlagSet(i.forceOverride) { return true }
        return i.noticeShown
            && !i.isDevelopmentBuild
            && !i.isDebugBuild
    }

    /// Should the first-run notice be offered? True only when everything except
    /// `noticeShown` would allow sending. We never show a "we collect stats"
    /// notice to someone who has already opted out, nor in a build (dev/debug)
    /// or environment (`DO_NOT_TRACK`) where nothing would ever be sent.
    public static func shouldOfferNotice(_ i: Inputs) -> Bool {
        !i.noticeShown
            && i.enabledPreference
            && !i.isDevelopmentBuild
            && !i.isDebugBuild
            && !envFlagSet(i.doNotTrack)
            && !envFlagSet(i.disableOverride)
    }

    /// The `console.dev` / `DO_NOT_TRACK` convention: a variable counts as set
    /// when it is present, non-empty, and not "0". Whitespace is trimmed.
    public static func envFlagSet(_ value: String?) -> Bool {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return false }
        return trimmed != "0"
    }
}
