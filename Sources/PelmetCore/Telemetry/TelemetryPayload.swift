import Foundation

/// A single JSON value in the telemetry payload. Deliberately closed to two
/// cases (string, bool) so the payload can only ever hold coarse, non-personal
/// facts. There is no `.int`, no `.dictionary`, no free-form `Any`: a field that
/// does not fit these two shapes cannot be added without a code change here, and
/// that change trips the schema test in `Tests/PelmetCoreTests`.
public enum TelemetryValue: Equatable {
    case string(String)
    case bool(Bool)

    /// The Foundation value handed to `JSONSerialization`. A Swift `Bool`
    /// bridges to a boolean `NSNumber`, so it serializes as `true`/`false`
    /// (never `0`/`1`).
    var jsonValue: Any {
        switch self {
        case let .string(value): return value
        case let .bool(value): return value
        }
    }
}

/// The one and only telemetry event Pelmet sends: an anonymous daily
/// "heartbeat". This type is the single source of truth for what goes on the
/// wire AND for the "what is sent" preview in Settings, so the two can never
/// drift.
///
/// It is a frozen struct of named fields (no dictionaries, no `Any`), lives in
/// `PelmetCore` with no UI or AppKit imports, and has no reference to the Shelf
/// or `NSRunningApplication`: it is structurally impossible for a user's menu
/// bar contents (the names of the other apps they run) to reach here. Adding or
/// renaming a field is a deliberate act that fails `TelemetryPayloadTests`,
/// which forces the `docs/TELEMETRY.md` + `CHANGELOG.md` update ritual.
public struct TelemetryPayload: Equatable {

    /// PostHog event name. One event type is enough: version adoption and
    /// update events are derivable from the same event (a stable `distinctID`
    /// whose `app_version` changes day over day).
    public static let eventName = "heartbeat"

    // MARK: Identity (top-level PostHog fields)

    /// Random per-install UUID. Derived from nothing, resettable by the user.
    public let distinctID: String
    /// Event time; encoded as an ISO 8601 UTC string.
    public let timestamp: Date

    // MARK: Data fields (PostHog `properties`)

    /// Marketing version only (`CFBundleShortVersionString`), e.g. "0.3.0".
    public let appVersion: String
    /// macOS major.minor only, e.g. "15.5". Never the patch or build.
    public let macOS: String
    /// "arm64" or "x86_64". Never the exact model identifier.
    public let arch: String
    /// Whether this Mac has a notched display (the one hardware fact the
    /// product actually branches on).
    public let notch: Bool
    public let shelfEnabled: Bool
    public let oneClickEnabled: Bool
    public let autoRehide: Bool
    /// Whether the user has ever actually hidden icons (tells a real user
    /// apart from a bounced install).
    public let managesItems: Bool
    /// Whether the previous session ended cleanly. This is the entire crash
    /// signal: a boolean, never a trace.
    public let prevSessionClean: Bool

    public init(
        distinctID: String,
        timestamp: Date,
        appVersion: String,
        macOS: String,
        arch: String,
        notch: Bool,
        shelfEnabled: Bool,
        oneClickEnabled: Bool,
        autoRehide: Bool,
        managesItems: Bool,
        prevSessionClean: Bool
    ) {
        self.distinctID = distinctID
        self.timestamp = timestamp
        self.appVersion = appVersion
        self.macOS = macOS
        self.arch = arch
        self.notch = notch
        self.shelfEnabled = shelfEnabled
        self.oneClickEnabled = oneClickEnabled
        self.autoRehide = autoRehide
        self.managesItems = managesItems
        self.prevSessionClean = prevSessionClean
    }

    // MARK: - Serialization

    /// The exact `properties` object sent to PostHog. The two `$`-prefixed keys
    /// are PostHog privacy directives: `$process_person_profile: false` keeps
    /// events anonymous (no person profile is ever created) and
    /// `$geoip_disable: true` skips server-side geo lookup on top of the
    /// project's "discard client IP" setting.
    public var properties: [String: TelemetryValue] {
        [
            "$process_person_profile": .bool(false),
            "$geoip_disable": .bool(true),
            "app_version": .string(appVersion),
            "macos": .string(macOS),
            "arch": .string(arch),
            "notch": .bool(notch),
            "shelf_enabled": .bool(shelfEnabled),
            "one_click_enabled": .bool(oneClickEnabled),
            "auto_rehide": .bool(autoRehide),
            "manages_items": .bool(managesItems),
            "prev_session_clean": .bool(prevSessionClean),
        ]
    }

    /// ISO 8601 UTC, e.g. "2026-07-13T00:04:11Z". Deterministic for a given
    /// `timestamp` (fixed formatter, UTC), so the body is byte-stable and
    /// unit-testable.
    static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private func eventObject(apiKey: String) -> [String: Any] {
        var props: [String: Any] = [:]
        for (key, value) in properties { props[key] = value.jsonValue }
        return [
            "api_key": apiKey,
            "event": Self.eventName,
            "distinct_id": distinctID,
            "timestamp": Self.iso8601(timestamp),
            "properties": props,
        ]
    }

    /// The request body for `POST https://us.i.posthog.com/i/v0/e/`.
    /// `.sortedKeys` makes the bytes deterministic (testable, cache-friendly).
    public func postHogBody(apiKey: String) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: eventObject(apiKey: apiKey),
            options: [.sortedKeys]
        )
    }

    /// Human-readable JSON for the Settings "what exactly is sent" disclosure.
    /// Built from the same object as the wire body, so the preview cannot lie
    /// about what ships.
    public func previewJSON(apiKey: String) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: eventObject(apiKey: apiKey),
            options: [.prettyPrinted, .sortedKeys]
        ), let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}
