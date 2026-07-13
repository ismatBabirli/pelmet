import CoreGraphics
import Foundation

/// The pure activation state machine: events in, effects out, no I/O.
/// The executor performs effects and feeds results back as events; every
/// rule about ordering, retries, verification and aborts lives HERE so it
/// is unit-testable without AppKit.
///
/// Rules encoded:
///  - strategies run in planner order; each click-ish step gets one
///    verification window (0.7s clicks, 1.2s AXPress — an AXPress "menu"
///    that collapses before ~1.1s is the known ghost-menu failure, so its
///    verification requires the window to persist, which the executor
///    implements);
///  - once ANY click was posted, a menu may already be open even though
///    verification missed it (detection is heuristic); every later step
///    is gated on a menu check, and an open menu finishes the session
///    successfully — never perform another step over the user's menu;
///  - exactly ONE retry total: the first strategy re-runs once after all
///    strategies exhaust, and only if no drag was performed;
///  - the drag path never retries; a failed drag ends the session;
///  - any abort releases mouse buttons BEFORE finishing, and schedules the
///    restore drag if the neighbor already moved;
///  - unverified after the FINAL click is soft success for targets that
///    were visible (or made visible by reflow) — many items open panels we
///    can't classify; for swallowed targets that never got a reflow click,
///    it is an honest failure instead.
public struct ActivationSession {

    public enum Event: Equatable {
        case begin
        /// The current strategy's action was performed (click posted, drag
        /// completed, clearance done).
        case stepCompleted
        /// The current strategy could not be performed at all.
        case stepFailed
        case verified(ActivationVerification)
        case verificationTimedOut
        /// Result of `Effect.checkMenuOpen`.
        case menuCheck(open: Bool)
        case aborted(ActivationFailure)
    }

    public enum Effect: Equatable {
        case perform(ActivationStrategy)
        /// Start polling for a newly opened menu window; feed back
        /// `.verified` or `.verificationTimedOut`. A non-nil `persistence`
        /// means a match only counts if the window is still present that
        /// much later (the AXPress ghost-menu rule).
        case startVerification(deadline: TimeInterval, persistence: TimeInterval?)
        /// One detector scan against the session baseline near the last
        /// click: did a menu open since the session began? Feed back
        /// `.menuCheck(open:)`.
        case checkMenuOpen
        /// Post a balanced mouse-up if any synthetic button might be down.
        case releaseMouseButtons
        /// After the session finishes and the opened menu closes: drag the
        /// neighbor back to its original slot.
        case restoreDrag(DragPlan)
        case finish(ActivationResult)
    }

    public static let clickVerification: TimeInterval = 0.7
    public static let axPressVerification: TimeInterval = 1.2
    /// An AXPress "menu" that collapses before ~1.1s is the known
    /// ghost-menu failure — a match must survive this long to count.
    public static let axPressMenuPersistence: TimeInterval = 1.1

    private let strategies: [ActivationStrategy]
    private let targetWasSwallowed: Bool
    private var index = 0
    private var didRetry = false
    /// True while the single first-strategy retry is in flight — the chain
    /// does NOT continue past it.
    private var retrying = false
    /// True between emitting `.checkMenuOpen` and receiving `.menuCheck` —
    /// any other `.menuCheck` is spurious and ignored.
    private var awaitingMenuGate = false
    private var dragPerformed: DragPlan?
    private var reflowClickHappened = false
    private var anyClickPosted = false
    private var finished = false

    public init(strategies: [ActivationStrategy], targetWasSwallowed: Bool) {
        self.strategies = strategies
        self.targetWasSwallowed = targetWasSwallowed
    }

    public mutating func handle(_ event: Event) -> [Effect] {
        guard !finished else { return [] }
        switch event {
        case .begin:
            guard let first = strategies.first else {
                return finish(.failed(.itemVanished))
            }
            return [.perform(first)]

        case .stepCompleted:
            switch current {
            case .syntheticClick:
                anyClickPosted = true
                return [.startVerification(deadline: Self.clickVerification, persistence: nil)]
            case .clickTargetAfterReflow:
                anyClickPosted = true
                reflowClickHappened = true
                return [.startVerification(deadline: Self.clickVerification, persistence: nil)]
            case .axPress:
                return [.startVerification(
                    deadline: Self.axPressVerification,
                    persistence: Self.axPressMenuPersistence
                )]
            case .appMenuClearance, .expandCollapsedBar:
                return advance()
            case .dragToExpose(let plan):
                dragPerformed = plan
                return advance()
            case nil:
                return []
            }

        case .stepFailed:
            if case .dragToExpose = current {
                // A drag that couldn't run means the make-room path is
                // closed; clicking "after reflow" without a reflow would
                // hit the dead zone again.
                return finish(.failed(.noRoomToExpose))
            }
            return advance()

        case .verified(let verification):
            return finish(.activated(verification))

        case .verificationTimedOut:
            return advance()

        case .menuCheck(let open):
            guard awaitingMenuGate else { return [] }
            awaitingMenuGate = false
            // An open menu is the success we were after — finishing here is
            // what keeps every remaining step from closing it under the user.
            if open { return finish(.activated(.menuOpened)) }
            guard let step = current else { return advance() }
            return [.perform(step)]

        case .aborted(let failure):
            var effects: [Effect] = [.releaseMouseButtons]
            effects.append(contentsOf: finish(.failed(failure)))
            return effects
        }
    }

    // MARK: - Internals

    private var current: ActivationStrategy? {
        if retrying { return strategies.first }
        return strategies.indices.contains(index) ? strategies[index] : nil
    }

    private mutating func advance() -> [Effect] {
        if !retrying {
            index += 1
            if let next = current {
                return gatedPerform(next)
            }
            // Exhausted. One retry of the FIRST strategy only, unless the
            // bar was already rearranged by a drag.
            if !didRetry, dragPerformed == nil, let first = strategies.first,
               case .syntheticClick = first {
                didRetry = true
                retrying = true
                return gatedPerform(first)
            }
        }
        if anyClickPosted, reflowClickHappened || !targetWasSwallowed {
            return finish(.activated(.unverified))
        }
        return finish(.failed(targetWasSwallowed ? .noRoomToExpose : .timedOut))
    }

    /// A posted click may have opened a menu the verification window missed
    /// — check before performing anything else over it. Before the first
    /// click nothing could be open, so perform directly.
    private mutating func gatedPerform(_ step: ActivationStrategy) -> [Effect] {
        guard anyClickPosted else { return [.perform(step)] }
        awaitingMenuGate = true
        return [.checkMenuOpen]
    }

    private mutating func finish(_ result: ActivationResult) -> [Effect] {
        finished = true
        var effects: [Effect] = []
        if let dragPerformed {
            effects.append(.restoreDrag(dragPerformed))
        }
        effects.append(.finish(result))
        return effects
    }
}
