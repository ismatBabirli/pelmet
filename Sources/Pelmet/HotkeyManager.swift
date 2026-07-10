import Carbon.HIToolbox
import os

/// Registers a global hotkey using the Carbon RegisterEventHotKey API.
/// Unlike NSEvent global monitors, this does NOT require the
/// Accessibility permission — ideal for a zero-permission MVP.
final class HotkeyManager {

    static let shared = HotkeyManager()

    var onToggle: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let logger = Logger(subsystem: "com.ismatbabirli.Pelmet", category: "HotkeyManager")

    /// Registers ⌥⌘B as the global toggle shortcut.
    /// - Returns: `true` if the hotkey is live; `false` if installation or
    ///   registration failed (usually another app already claimed ⌥⌘B).
    func register() -> Bool {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ -> OSStatus in
                DispatchQueue.main.async {
                    HotkeyManager.shared.onToggle?()
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
            return false
        }

        let hotKeyID = EventHotKeyID(signature: fourCharCode("PLMT"), id: 1)
        let hotKeyStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_B),
            UInt32(cmdKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if hotKeyStatus != noErr {
            // Usually means another app already claimed ⌥⌘B.
            logger.error("Failed to register ⌥⌘B global hotkey (OSStatus \(hotKeyStatus))")
            return false
        }
        return true
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
        hotKeyRef = nil
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
