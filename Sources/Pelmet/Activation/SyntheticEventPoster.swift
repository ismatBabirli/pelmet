import AppKit
import CoreGraphics
import PelmetCore

/// Posts synthetic mouse events to activate status items. Warps the cursor
/// so the window server's hit-test matches the event location (status-item
/// hit-testing happens in WindowServer at the cursor, not per-PID), then
/// restores it. Requires the Accessibility grant (TCC's PostEvent bucket
/// rides along); the app must be signed for Tahoe's synthetic-event gate.
protocol EventPosting: AnyObject {
    /// AppKit-coordinate click. Returns false if the event source couldn't
    /// be created.
    @discardableResult func click(atAppKit point: CGPoint) -> Bool
    @discardableResult func commandDrag(fromAppKit: CGPoint, toAppKit: CGPoint) -> Bool
    /// Belt-and-braces: post a bare mouse-up in case a synthetic button is
    /// stuck down after an abort.
    func releaseMouseButtons()
}

final class SyntheticEventPoster: EventPosting {

    /// Tag on every event we post, so our own event taps (and debugging)
    /// can recognize Pelmet-origin events. "PLMT".
    static let sourceUserData: Int64 = 0x504C4D54

    private var primaryMaxY: CGFloat { NSScreen.screens.first?.frame.maxY ?? 0 }

    @discardableResult
    func click(atAppKit point: CGPoint) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return false }
        source.userData = Self.sourceUserData
        let cg = ScreenCoordinates.cgPoint(fromAppKit: point, primaryMaxY: primaryMaxY)

        let cursorWasNear = distance(NSEvent.mouseLocation, point) < 6
        let restore = NSEvent.mouseLocation
        if !cursorWasNear {
            hideCursor()
            CGAssociateMouseAndMouseCursorPosition(0)
            CGWarpMouseCursorPosition(cg)
        }
        defer {
            if !cursorWasNear {
                let restoreCG = ScreenCoordinates.cgPoint(fromAppKit: restore, primaryMaxY: primaryMaxY)
                CGWarpMouseCursorPosition(restoreCG)
                CGAssociateMouseAndMouseCursorPosition(1)
                showCursor()
            }
        }
        usleep(20_000) // 20ms settle after the warp

        post(source, type: .leftMouseDown, at: cg, clickState: 1)
        usleep(40_000)
        post(source, type: .leftMouseUp, at: cg, clickState: 1)
        return true
    }

    @discardableResult
    func commandDrag(fromAppKit: CGPoint, toAppKit: CGPoint) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return false }
        source.userData = Self.sourceUserData
        let from = ScreenCoordinates.cgPoint(fromAppKit: fromAppKit, primaryMaxY: primaryMaxY)
        let to = ScreenCoordinates.cgPoint(fromAppKit: toAppKit, primaryMaxY: primaryMaxY)

        let restore = NSEvent.mouseLocation
        hideCursor()
        CGAssociateMouseAndMouseCursorPosition(0)
        CGWarpMouseCursorPosition(from)
        defer {
            let restoreCG = ScreenCoordinates.cgPoint(fromAppKit: restore, primaryMaxY: primaryMaxY)
            CGWarpMouseCursorPosition(restoreCG)
            CGAssociateMouseAndMouseCursorPosition(1)
            showCursor()
        }
        usleep(20_000)

        post(source, type: .leftMouseDown, at: from, flags: .maskCommand)
        let steps = 10
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let point = CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
            post(source, type: .leftMouseDragged, at: point, flags: .maskCommand)
            usleep(16_000)
        }
        post(source, type: .leftMouseUp, at: to, flags: .maskCommand)
        return true
    }

    /// The synthetic sequence drives the REAL cursor (warp + event
    /// positions), which reads as "my mouse is moving by itself". Hide it
    /// for the few hundred ms the sequence runs. Balanced hide/show; may be
    /// a no-op for background apps on some macOS versions — harmless then.
    private func hideCursor() {
        CGDisplayHideCursor(CGMainDisplayID())
    }

    private func showCursor() {
        CGDisplayShowCursor(CGMainDisplayID())
    }

    func releaseMouseButtons() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        source.userData = Self.sourceUserData
        let location = ScreenCoordinates.cgPoint(fromAppKit: NSEvent.mouseLocation, primaryMaxY: primaryMaxY)
        post(source, type: .leftMouseUp, at: location)
    }

    // MARK: - Helpers

    private func post(
        _ source: CGEventSource,
        type: CGEventType,
        at point: CGPoint,
        flags: CGEventFlags = [],
        clickState: Int64? = nil
    ) {
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else { return }
        event.flags = flags
        if let clickState { event.setIntegerValueField(.mouseEventClickState, value: clickState) }
        event.post(tap: .cghidEventTap)
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
