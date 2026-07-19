import Foundation
import Testing
@testable import PelmetCore

struct TelemetryPayloadTests {

    private func samplePayload(
        prevSessionClean: Bool = true
    ) -> TelemetryPayload {
        TelemetryPayload(
            distinctID: "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d",
            timestamp: Date(timeIntervalSince1970: 1_752_364_800), // 2025-07-13T00:00:00Z
            appVersion: "0.3.0",
            macOS: "15.5",
            arch: "arm64",
            notch: true,
            shelfEnabled: true,
            oneClickEnabled: false,
            autoRehide: true,
            managesItems: true,
            prevSessionClean: prevSessionClean
        )
    }

    /// The heart of the "no field creep, nothing leaks" guarantee: the wire
    /// payload's key set is exactly this and nothing more. If someone adds a
    /// field to `TelemetryPayload` this test fails, forcing the TELEMETRY.md +
    /// CHANGELOG update. If the field were ever something about the user's menu
    /// bar, this is where it would be caught.
    @Test func testExactPropertyKeySet() throws {
        let body = try samplePayload().postHogBody(apiKey: "phc_test")
        let json = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        let properties = json["properties"] as! [String: Any]

        let expected: Set<String> = [
            "$process_person_profile", "$geoip_disable",
            "app_version", "macos", "arch", "notch",
            "shelf_enabled", "one_click_enabled", "auto_rehide",
            "manages_items", "prev_session_clean",
        ]
        #expect(Set(properties.keys) == expected)

        // Top level: exactly the four PostHog envelope fields.
        #expect(Set(json.keys) == ["api_key", "event", "distinct_id", "timestamp", "properties"])
    }

    @Test func testAnonymityAndGeoFlags() throws {
        let body = try samplePayload().postHogBody(apiKey: "phc_test")
        let json = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        let properties = json["properties"] as! [String: Any]

        #expect(properties["$process_person_profile"] as? Bool == false)
        #expect(properties["$geoip_disable"] as? Bool == true)
    }

    @Test func testEnvelopeFields() throws {
        let body = try samplePayload().postHogBody(apiKey: "phc_secret")
        let json = try JSONSerialization.jsonObject(with: body) as! [String: Any]

        #expect(json["api_key"] as? String == "phc_secret")
        #expect(json["event"] as? String == "heartbeat")
        #expect(json["distinct_id"] as? String == "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d")
        #expect(json["timestamp"] as? String == "2025-07-13T00:00:00Z")
    }

    @Test func testDataFieldsPassThrough() throws {
        let body = try samplePayload(prevSessionClean: false).postHogBody(apiKey: "k")
        let json = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        let properties = json["properties"] as! [String: Any]

        #expect(properties["app_version"] as? String == "0.3.0")
        #expect(properties["macos"] as? String == "15.5")
        #expect(properties["arch"] as? String == "arm64")
        #expect(properties["notch"] as? Bool == true)
        #expect(properties["shelf_enabled"] as? Bool == true)
        #expect(properties["one_click_enabled"] as? Bool == false)
        #expect(properties["auto_rehide"] as? Bool == true)
        #expect(properties["manages_items"] as? Bool == true)
        #expect(properties["prev_session_clean"] as? Bool == false)
    }

    /// Booleans must serialize as JSON `true`/`false`, never `0`/`1`.
    @Test func testBooleansAreJSONBooleans() throws {
        let body = try samplePayload().postHogBody(apiKey: "k")
        let text = String(data: body, encoding: .utf8)!
        #expect(text.contains("\"notch\":true"))
        #expect(text.contains("\"$process_person_profile\":false"))
        #expect(!text.contains("\"notch\":1"))
    }

    /// Deterministic bytes: same payload encodes identically every time.
    @Test func testDeterministicEncoding() throws {
        let a = try samplePayload().postHogBody(apiKey: "k")
        let b = try samplePayload().postHogBody(apiKey: "k")
        #expect(a == b)
    }

    @Test func testPreviewJSONIsReadableAndHonest() {
        let preview = samplePayload().previewJSON(apiKey: "phc_test")
        // Pretty-printed (has newlines) and shows the real field names.
        #expect(preview.contains("\n"))
        #expect(preview.contains("prev_session_clean"))
        #expect(preview.contains("heartbeat"))
    }

    @Test func testISO8601IsUTC() {
        let date = Date(timeIntervalSince1970: 0)
        #expect(TelemetryPayload.iso8601(date) == "1970-01-01T00:00:00Z")
    }
}
