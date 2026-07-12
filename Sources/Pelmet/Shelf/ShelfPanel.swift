import AppKit

/// The Shelf's window: borderless, non-activating, floating just below the
/// menu bar (level 25 — the same `.statusBar` level status items live at,
/// verified against `NSWindow.Level.mainMenu.rawValue == 24`). It follows
/// the active Space and shows over fullscreen apps as an auxiliary panel.
///
/// IMPORTANT: the panel's width must stay ABOVE 300pt. It shares the
/// status-item window level, and `MenuBarLayoutClassifier` rejects windows
/// wider than `maxPlausibleItemWidth` (300) — plus the panel sits below the
/// menu bar band. Two independent guards keep Pelmet from classifying its
/// own Shelf as a menu bar item.
final class ShelfPanel: NSPanel {

    /// Arrow keys, Return and Esc arrive here from `keyDown` and are routed
    /// by the controller; SwiftUI focus in borderless panels is unreliable
    /// on macOS 13, so keyboard handling stays at the AppKit layer.
    var onKeyCommand: ((KeyCommand) -> Bool)?

    enum KeyCommand {
        case moveUp, moveDown, activate, cancel
    }

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        level = .statusBar
        collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .moveToActiveSpace]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        animationBehavior = .none // fades are driven manually, gated on Reduce Motion
    }

    /// Non-activating panels may still become key so keyboard users can
    /// drive the Shelf without activating Pelmet.
    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        let command: KeyCommand?
        switch event.keyCode {
        case 126: command = .moveUp
        case 125: command = .moveDown
        case 36, 76: command = .activate   // Return, keypad Enter
        case 53: command = .cancel         // Esc
        default: command = nil
        }
        if let command, onKeyCommand?(command) == true { return }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        _ = onKeyCommand?(.cancel)
    }
}
