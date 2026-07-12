import AppKit
import ApplicationServices
import PelmetCore

/// One menu bar extra as the Accessibility API reports it. Holds the live
/// AXUIElement so activation can attempt AXPress without re-enumerating.
struct AXExtraObservation {
    let pid: pid_t
    let title: String?
    let axDescription: String?
    /// AppKit screen coordinates; nil when position/size were unreadable.
    let frameAppKit: CGRect?
    let element: AXUIElement
}

/// Seam for the AX layer so the engine (and tests) never touch AXUIElement
/// directly. Call ONLY off the main thread — AX round-trips to unresponsive
/// apps block until the messaging timeout.
protocol MenuBarExtrasReading: AnyObject {
    /// The given app's menu bar extras (including notch-hidden ones — their
    /// AX elements stay alive with valid frames).
    func extras(forPID pid: pid_t, primaryMaxY: CGFloat) -> [AXExtraObservation]
}

final class LiveAXMenuBarExtrasReader: MenuBarExtrasReading {

    /// Per-app cap so one hung process can't stall a sweep for long.
    private static let messagingTimeout: Float = 1.0

    func extras(forPID pid: pid_t, primaryMaxY: CGFloat) -> [AXExtraObservation] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Self.messagingTimeout)

        guard let extrasBar = copyElement(app, kAXExtrasMenuBarAttribute),
              let children = copyElementArray(extrasBar, kAXChildrenAttribute)
        else { return [] }

        return children.map { child in
            AXExtraObservation(
                pid: pid,
                title: copyString(child, kAXTitleAttribute),
                axDescription: copyString(child, kAXDescriptionAttribute),
                frameAppKit: copyFrame(child, primaryMaxY: primaryMaxY),
                element: child
            )
        }
    }

    // MARK: - Raw attribute helpers (every copy checked; partial data wins
    // over no data)

    private func copyValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return error == .success ? value : nil
    }

    private func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copyValue(element, attribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func copyElementArray(_ element: AXUIElement, _ attribute: String) -> [AXUIElement]? {
        guard let value = copyValue(element, attribute),
              let array = value as? [AnyObject] else { return nil }
        return array.compactMap {
            CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil
        }
    }

    private func copyString(_ element: AXUIElement, _ attribute: String) -> String? {
        copyValue(element, attribute) as? String
    }

    private func copyFrame(_ element: AXUIElement, primaryMaxY: CGFloat) -> CGRect? {
        Self.frame(of: element, primaryMaxY: primaryMaxY)
    }

    /// Live frame of an AX element (AppKit coords), bounded by a messaging
    /// timeout so a hung app fails fast. Call off-main only. This is how
    /// cached observations get FRESH positions on every directory rebuild —
    /// items move every time Pelmet collapses/expands, so cached frames rot
    /// within seconds while elements and titles stay valid.
    static func frame(
        of element: AXUIElement,
        primaryMaxY: CGFloat,
        timeout: Float = 0.25
    ) -> CGRect? {
        AXUIElementSetMessagingTimeout(element, timeout)
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size),
              size.width > 0, size.height > 0
        else { return nil }

        // AX positions are CG global top-left origin.
        return ScreenCoordinates.appKitRect(
            fromCG: CGRect(origin: position, size: size),
            primaryMaxY: primaryMaxY
        )
    }
}
