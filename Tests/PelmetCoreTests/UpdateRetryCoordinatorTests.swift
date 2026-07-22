import Foundation
import Testing
@testable import PelmetCore

struct UpdateRetryCoordinatorTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func offlineFailureWaitsForConnectivity() {
        var coordinator = UpdateRetryCoordinator()
        coordinator.recordNetworkFailure(now: now, connectivityAvailable: false)

        #expect(coordinator.phase == .waitingForConnectivity)
        #expect(coordinator.snapshot?.attemptCount == 0)
    }

    @Test func reconnectDebouncesForThirtySeconds() {
        var coordinator = UpdateRetryCoordinator()
        coordinator.recordNetworkFailure(now: now, connectivityAvailable: false)
        coordinator.connectivityChanged(available: true, now: now)

        #expect(coordinator.phase == .scheduled(now.addingTimeInterval(30)))
    }

    @Test func availablePathUsesBackoffSequence() {
        var coordinator = UpdateRetryCoordinator()
        coordinator.recordNetworkFailure(now: now, connectivityAvailable: true)
        #expect(coordinator.phase == .scheduled(now.addingTimeInterval(5 * 60)))

        let firstDue = now.addingTimeInterval(5 * 60)
        #expect(coordinator.retryTimerFired(now: firstDue, updaterCanCheck: true) == .performRetry)
        coordinator.recordNetworkFailure(now: firstDue, connectivityAvailable: true)
        #expect(coordinator.phase == .scheduled(firstDue.addingTimeInterval(15 * 60)))

        let secondDue = firstDue.addingTimeInterval(15 * 60)
        #expect(coordinator.retryTimerFired(now: secondDue, updaterCanCheck: true) == .performRetry)
        coordinator.recordNetworkFailure(now: secondDue, connectivityAvailable: true)
        #expect(coordinator.phase == .scheduled(secondDue.addingTimeInterval(60 * 60)))
    }

    @Test func threeRecoveryChecksExhaustTheEpisode() {
        var coordinator = UpdateRetryCoordinator()
        var date = now

        for delay in UpdateRetryCoordinator.backoffDelays {
            coordinator.recordNetworkFailure(now: date, connectivityAvailable: true)
            date = date.addingTimeInterval(delay)
            #expect(coordinator.retryTimerFired(now: date, updaterCanCheck: true) == .performRetry)
        }

        #expect(coordinator.recordNetworkFailure(now: date, connectivityAvailable: true) == .exhausted)
        #expect(coordinator.phase == .inactive)
    }

    @Test func busyUpdaterDoesNotConsumeAttemptOrOverlap() {
        var coordinator = UpdateRetryCoordinator()
        coordinator.recordNetworkFailure(now: now, connectivityAvailable: true)
        let due = now.addingTimeInterval(5 * 60)

        #expect(coordinator.retryTimerFired(now: due, updaterCanCheck: false) == .none)
        #expect(coordinator.snapshot?.attemptCount == 0)
        #expect(coordinator.phase == .scheduled(due.addingTimeInterval(60)))
        #expect(coordinator.retryTimerFired(now: due, updaterCanCheck: true) == .none)
    }

    @Test func persistedRetryResumesAfterRelaunch() {
        let snapshot = UpdateRetrySnapshot(
            attemptCount: 1,
            mode: .checking
        )
        var coordinator = UpdateRetryCoordinator(snapshot: snapshot)
        coordinator.resume(now: now, connectivityAvailable: true, automaticallyChecks: true)

        #expect(coordinator.phase == .scheduled(now.addingTimeInterval(30)))
        #expect(coordinator.snapshot?.attemptCount == 1)
    }

    @Test func invalidPersistedAttemptCountIsDiscarded() {
        let encoded = """
        {"attemptCount":-1,"mode":"scheduled","nextRetryDate":0}
        """.data(using: .utf8)!
        let snapshot = try! JSONDecoder().decode(UpdateRetrySnapshot.self, from: encoded)

        let coordinator = UpdateRetryCoordinator(snapshot: snapshot)

        #expect(coordinator.phase == .inactive)
    }

    @Test func optOutAndSuccessClearPendingRetry() {
        var optedOut = UpdateRetryCoordinator(
            snapshot: UpdateRetrySnapshot(attemptCount: 1, mode: .waitingForConnectivity)
        )
        optedOut.resume(now: now, connectivityAvailable: true, automaticallyChecks: false)
        #expect(optedOut.phase == .inactive)

        var succeeded = UpdateRetryCoordinator(
            snapshot: UpdateRetrySnapshot(attemptCount: 1, mode: .waitingForConnectivity)
        )
        succeeded.clear()
        #expect(succeeded.phase == .inactive)
    }

    @Test func pathFlapRestartsReconnectDebounce() {
        var coordinator = UpdateRetryCoordinator()
        coordinator.recordNetworkFailure(now: now, connectivityAvailable: false)
        coordinator.connectivityChanged(available: true, now: now)
        coordinator.connectivityChanged(available: false, now: now.addingTimeInterval(10))
        coordinator.connectivityChanged(available: true, now: now.addingTimeInterval(20))

        #expect(coordinator.phase == .scheduled(now.addingTimeInterval(50)))
    }
}
