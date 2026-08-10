import AppKit
import PelmetCore

/// The control that records a global shortcut.
///
/// Subclasses `NSButton` rather than drawing an `NSView`, which buys the focus
/// ring, the light and dark appearance, Tab-loop membership, Space-to-activate and
/// the `.button` accessibility role for free, and looks native by construction.
/// Nothing here animates, so there is no reduce-motion branch to write.
final class ShortcutRecorderButton: NSButton {

    /// Returns a rejection to display, or nil when the combination was accepted.
    var onRecord: ((KeyCombo) -> HotkeyRejection?)?
    var onClear: (() -> Void)?

    var combo: KeyCombo? {
        didSet { refreshTitle() }
    }

    /// The Settings row label, used to build the VoiceOver label.
    var rowLabel = "" {
        didSet { setAccessibilityLabel("\(rowLabel) shortcut") }
    }

    private(set) var isRecording = false
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?

    private static let idlePrompt = "Record Shortcut"
    private static let recordingPrompt = "Type a shortcut…"

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(buttonPressed)
        refreshTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used; this control is created in code")
    }

    deinit {
        // Never leave the global hotkeys suspended.
        teardownRecording()
    }

    override var acceptsFirstResponder: Bool { true }

    @objc private func buttonPressed() {
        isRecording ? endRecording() : beginRecording()
    }

    /// Return activates a push button only when it is the window's default button,
    /// so handle it here. Space already arrives as the button's action.
    override func keyDown(with event: NSEvent) {
        if !isRecording, event.keyCode == 36 || event.keyCode == 76 {
            beginRecording()
            return
        }
        super.keyDown(with: event)
    }

    /// Belt to the local monitor's braces. If monitor ordering ever changes, this
    /// still claims a ⌘-bearing keystroke before anything else can act on it.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        return handle(event)
    }

    override func resignFirstResponder() -> Bool {
        endRecording()
        return super.resignFirstResponder()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { endRecording() }
        super.viewWillMove(toWindow: newWindow)
    }

    private func beginRecording() {
        guard !isRecording else { return }
        isRecording = true

        // Pelmet's own Carbon hotkeys consume their keystroke before any app sees
        // it, so the current ⌥⌘B would toggle the menu bar instead of landing here.
        HotkeyManager.shared.suspendForRecording()

        // A local monitor is invoked from NSApplication.sendEvent, ahead of the
        // window's key-equivalent dispatch, so a SwiftUI .keyboardShortcut, a
        // default or cancel button, or Escape-as-cancelOperation cannot eat the
        // keystroke first. Scoped to this window, and returning nil swallows it.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) {
            [weak self] event in
            guard let self, self.isRecording, event.window === self.window else { return event }
            return self.handle(event) ? nil : event
        }

        // Recording must not outlive focus, or the suspended hotkeys stay dead.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            self?.endRecording()
        }

        refreshTitle()
    }

    private func endRecording() {
        guard isRecording else { return }
        teardownRecording()
        refreshTitle()
    }

    private func teardownRecording() {
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        HotkeyManager.shared.resumeAfterRecording()
    }

    /// Returns true when the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        let modifiers = KeyModifiers(nsEventFlags: event.modifierFlags)

        switch event.type {
        case .flagsChanged:
            // Live preview of what is held, which is what makes the control feel
            // responsive. A modifier alone never produces a keyDown, so this is
            // also why modifier-only presses need no rejection path here.
            title = modifiers.isEmpty ? Self.recordingPrompt : modifiers.displayString
            return true

        case .keyDown:
            // Note: `case 51, 117 where ...` would bind the where clause to the
            // last pattern only, so these are guarded separately.
            if event.keyCode == 53, modifiers.isEmpty {
                endRecording()
                return true
            }
            if event.keyCode == 51 || event.keyCode == 117,
               modifiers.isDisjoint(with: .primary) {
                onClear?()
                // Adopt the new value here rather than waiting for SwiftUI to
                // push it back, so the title never flashes the old shortcut.
                combo = nil
                endRecording()
                announceValue()
                return true
            }

            let candidate = KeyCombo(keyCode: event.keyCode, modifiers: modifiers)
            if onRecord?(candidate) != nil {
                // Stay armed: the pane prints the specific reason, and the user
                // can try again without a second click.
                title = Self.recordingPrompt
                return true
            }
            combo = candidate
            endRecording()
            announceValue()
            return true

        default:
            return false
        }
    }

    private func refreshTitle() {
        if isRecording {
            title = Self.recordingPrompt
        } else if let combo {
            title = HotkeyDisplay.string(for: combo)
        } else {
            title = Self.idlePrompt
        }
    }

    private func announceValue() {
        NSAccessibility.post(element: self, notification: .valueChanged)
    }

    // MARK: - Accessibility

    override func accessibilityRole() -> NSAccessibility.Role? { .button }

    override func accessibilityValue() -> Any? {
        if isRecording { return "Recording. Press the keys you want, or Escape to cancel." }
        guard let combo else { return "No shortcut" }
        return HotkeyDisplay.spoken(for: combo)
    }

    override func accessibilityHelp() -> String? {
        "Press Space to record a new shortcut. Delete removes it."
    }

    override func accessibilityPerformPress() -> Bool {
        beginRecording()
        return true
    }
}
