import Foundation
import Testing
@testable import PelmetCore

struct HeartbeatScheduleTests {

    // 2025-07-13T12:00:00Z
    private let noon = Date(timeIntervalSince1970: 1_752_408_000)

    @Test func testDayKeyIsUTC() {
        #expect(HeartbeatSchedule.dayKey(for: Date(timeIntervalSince1970: 0)) == "1970-01-01")
        #expect(HeartbeatSchedule.dayKey(for: noon) == "2025-07-13")
    }

    @Test func testSendsWhenNeverSent() {
        #expect(HeartbeatSchedule.shouldSend(lastSentDay: nil, now: noon))
    }

    @Test func testBlocksSameDay() {
        let today = HeartbeatSchedule.dayKey(for: noon)
        #expect(!HeartbeatSchedule.shouldSend(lastSentDay: today, now: noon))
    }

    @Test func testSendsNextDay() {
        #expect(HeartbeatSchedule.shouldSend(lastSentDay: "2025-07-12", now: noon))
    }

    /// The day boundary is UTC midnight, not local: 23:59Z and 00:01Z are
    /// different days regardless of the machine's timezone.
    @Test func testUTCBoundary() {
        let justBefore = Date(timeIntervalSince1970: 1_752_364_740) // 2025-07-12T23:59:00Z
        let justAfter = Date(timeIntervalSince1970: 1_752_364_860)  // 2025-07-13T00:01:00Z
        #expect(HeartbeatSchedule.dayKey(for: justBefore) == "2025-07-12")
        #expect(HeartbeatSchedule.dayKey(for: justAfter) == "2025-07-13")
        // Sent just before midnight, a moment later it is a new day => send.
        #expect(HeartbeatSchedule.shouldSend(lastSentDay: "2025-07-12", now: justAfter))
    }

    @Test func testCoolingOffPassesWhenNotShownThisSession() {
        // Shown in a previous session (a launch has since happened).
        #expect(HeartbeatSchedule.coolingOffElapsed(
            noticeShownThisSession: false, noticeShownAt: nil, now: noon))
        #expect(HeartbeatSchedule.coolingOffElapsed(
            noticeShownThisSession: false, noticeShownAt: noon, now: noon))
    }

    @Test func testCoolingOffHoldsWithinDayOfShowing() {
        let oneHourLater = noon.addingTimeInterval(3600)
        #expect(!HeartbeatSchedule.coolingOffElapsed(
            noticeShownThisSession: true, noticeShownAt: noon, now: oneHourLater))
    }

    @Test func testCoolingOffElapsesAfter24h() {
        let dayLater = noon.addingTimeInterval(24 * 3600)
        #expect(HeartbeatSchedule.coolingOffElapsed(
            noticeShownThisSession: true, noticeShownAt: noon, now: dayLater))
    }
}
