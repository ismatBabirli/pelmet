import Carbon.HIToolbox
import os

/// Registers global hotkeys using the Carbon RegisterEventHotKey API.
/// Unlike NSEvent global monitors, this does NOT require the
/// Accessibility permission — ideal for a zero-permission core.
final class HotkeyManager {

    static let shared = HotkeyManager()

    var onToggle: (() -> Void)?
    var onShelf: (() -> Void)?

    struct Registration {
        let toggle: Bool
        let shelf: Bool
    }

    private enum HotkeyID: UInt32 {
        case toggle = 1
        case shelf = 2
    }

    private var toggleHotKeyRef: EventHotKeyRef?
    private var shelfHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let logger = Logger(subsystem: "com.ismatbabirli.Pelmet", category: "HotkeyManager")

    /// Registers ⌥⌘B (toggle) and ⌥⌘N (Shelf) as global shortcuts.
    /// Each registration can fail independently — usually because another
    /// app already claimed the combination.
    func register() -> Registration {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }
                DispatchQueue.main.async {
                    switch HotkeyID(rawValue: hotKeyID.id) {
                    case .toggle: HotkeyManager.shared.onToggle?()
                    case .shelf: HotkeyManager.shared.onShelf?()
                    case nil: break
                    }
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
        guard handlerStatus == noErr else {
            logger.error("Failed to install hotkey event handler (OSStatus \(handlerStatus))")
            return Registration(toggle: false, shelf: false)
        }

        let toggle = registerHotkey(
            id: .toggle, keyCode: UInt32(kVK_ANSI_B), ref: &toggleHotKeyRef, label: "⌥⌘B"
        )
        let shelf = registerHotkey(
            id: .shelf, keyCode: UInt32(kVK_ANSI_N), ref: &shelfHotKeyRef, label: "⌥⌘N"
        )
        return Registration(toggle: toggle, shelf: shelf)
    }

    private func registerHotkey(
        id: HotkeyID,
        keyCode: UInt32,
        ref: inout EventHotKeyRef?,
        label: String
    ) -> Bool {
        let hotKeyID = EventHotKeyID(signature: fourCharCode("PLMT"), id: id.rawValue)
        let status = RegisterEventHotKey(
            keyCode,
            UInt32(cmdKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status != noErr {
            // Usually means another app already claimed the combination.
            logger.error("Failed to register \(label) global hotkey (OSStatus \(status))")
            return false
        }
        return true
    }

    func unregister() {
        if let toggleHotKeyRef { UnregisterEventHotKey(toggleHotKeyRef) }
        if let shelfHotKeyRef { UnregisterEventHotKey(shelfHotKeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
        toggleHotKeyRef = nil
        shelfHotKeyRef = nil
        eventHandlerRef = nil
    }
}

private func fourCharCode(_ string: String) -> FourCharCode {
    var result: FourCharCode = 0
    for scalar in string.unicodeScalars.prefix(4) {
        result = (result << 8) + FourCharCode(scalar.value & 0xFF)
    }
    return result
}
