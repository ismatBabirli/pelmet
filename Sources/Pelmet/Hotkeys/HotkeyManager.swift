import Carbon.HIToolbox
import Foundation
import PelmetCore
import os

/// Registers Pelmet's global hotkeys using the Carbon `RegisterEventHotKey` API.
///
/// Unlike NSEvent global monitors, this does NOT require the Accessibility
/// permission, which is what lets the shortcuts stay part of the zero-permission
/// core. Shortcuts are user-recordable, so registration is dynamic: a live edit
/// re-registers without tearing down the shared event handler.
final class HotkeyManager {

    static let shared = HotkeyManager()

    var onToggle: (() -> Void)?
    var onShelf: (() -> Void)?

    enum Outcome: Equatable {
        case registered
        /// Carbon refused. Almost always `eventHotKeyExistsErr`, meaning another
        /// app already owns the combination.
        case unavailable
        /// No shortcut assigned, because the user cleared it.
        case none
    }

    private(set) var bindings: HotkeyBindings = .defaults
    private(set) var outcomes: [HotkeyAction: Outcome] = [:]

    private var refs: [HotkeyAction: EventHotKeyRef] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private var isApplying = false
    private var isSuspended = false
    private let logger = Logger(subsystem: "com.ismatbabirli.Pelmet", category: "HotkeyManager")

    /// Loads the stored shortcuts and registers them. Call once at launch.
    func start() {
        apply(Preferences.hotkeyBindings)
    }

    /// Validates, persists and re-registers one action. Returns the rejection to
    /// show the user, or nil when the combination was accepted. Pass nil to clear.
    ///
    /// The pref keys are written only here, never from a view.
    @discardableResult
    func setShortcut(_ combo: KeyCombo?, for action: HotkeyAction) -> HotkeyRejection? {
        if let combo {
            let rejection = HotkeyValidator.validate(
                combo,
                for: action,
                against: bindings,
                systemReserved: SystemReservedShortcuts.current()
            )
            if let rejection { return rejection }
        }
        Preferences.setHotkeyRecord(HotkeyRecord(combo: combo), for: action)
        var updated = bindings
        updated[action] = combo
        apply(updated)
        return nil
    }

    /// Removes both stored keys rather than writing the defaults into them, so
    /// "absent means the shipped default" keeps holding and a future change of
    /// default still reaches anyone who never customized.
    func restoreDefaults() {
        for action in HotkeyAction.allCases {
            Preferences.setHotkeyRecord(nil, for: action)
        }
        apply(Preferences.hotkeyBindings)
    }

    /// While the recorder is armed, Pelmet's own hotkeys must stand down. A Carbon
    /// hotkey consumes its keystroke before any app sees it, so pressing the
    /// current ⌥⌘B inside the recorder would toggle the menu bar instead of being
    /// recorded.
    func suspendForRecording() {
        guard !isSuspended else { return }
        isSuspended = true
        for action in HotkeyAction.allCases {
            unregister(action)
        }
    }

    func resumeAfterRecording() {
        guard isSuspended else { return }
        isSuspended = false
        apply(bindings)
    }

    func unregister() {
        for action in HotkeyAction.allCases {
            unregister(action)
        }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
        eventHandlerRef = nil
    }

    /// Called from the Carbon trampoline once the action has been identified.
    fileprivate func perform(_ action: HotkeyAction) {
        switch action {
        case .toggle: onToggle?()
        case .shelf: onShelf?()
        }
    }

    private func apply(_ newBindings: HotkeyBindings) {
        bindings = newBindings
        guard !isApplying else { return }
        isApplying = true
        defer { isApplying = false }

        guard !isSuspended else {
            publish()
            return
        }

        guard ensureHandlerInstalled() else {
            for action in HotkeyAction.allCases {
                outcomes[action] = newBindings[action] == nil ? Outcome.none : .unavailable
            }
            publish()
            return
        }

        // Two passes on purpose. RegisterEventHotKey refuses a combination that is
        // still registered, INCLUDING one of Pelmet's own, so swapping the two
        // actions' shortcuts would fail if the old refs were alive during the
        // register pass.
        for action in HotkeyAction.allCases {
            unregister(action)
        }
        for action in HotkeyAction.allCases {
            guard let combo = newBindings[action] else {
                outcomes[action] = Outcome.none
                continue
            }
            outcomes[action] = register(combo, for: action)
        }
        publish()
    }

    /// Idempotent, so live re-registration never tears the shared handler down.
    private func ensureHandlerInstalled() -> Bool {
        guard eventHandlerRef == nil else { return true }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
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
                guard let action = HotkeyAction.allCases.first(where: { $0.eventID == hotKeyID.id })
                else { return noErr }
                DispatchQueue.main.async {
                    HotkeyManager.shared.perform(action)
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
        guard status == noErr else {
            logger.error("Failed to install hotkey event handler (OSStatus \(status))")
            return false
        }
        return true
    }

    private func register(_ combo: KeyCombo, for action: HotkeyAction) -> Outcome {
        guard combo.isPlausible else {
            logger.error("Refusing to register an implausible keycode \(combo.keyCode)")
            return .unavailable
        }
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: fourCharCode("PLMT"), id: action.eventID)
        let status = RegisterEventHotKey(
            UInt32(combo.keyCode),
            combo.modifiers.carbonFlags,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            // Usually eventHotKeyExistsErr: another app already claimed it.
            logger.error(
                "Failed to register \(combo.displayString(), privacy: .public) (OSStatus \(status))"
            )
            return .unavailable
        }
        refs[action] = ref
        return .registered
    }

    private func unregister(_ action: HotkeyAction) {
        guard let ref = refs.removeValue(forKey: action) else { return }
        UnregisterEventHotKey(ref)
    }

    private func publish() {
        NotificationCenter.default.post(name: .pelmetHotkeyBindingsDidChange, object: nil)
    }
}

private func fourCharCode(_ string: String) -> FourCharCode {
    var result: FourCharCode = 0
    for scalar in string.unicodeScalars.prefix(4) {
        result = (result << 8) + FourCharCode(scalar.value & 0xFF)
    }
    return result
}
