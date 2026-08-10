import PelmetCore
import SwiftUI

/// SwiftUI wrapper around `ShortcutRecorderButton`, for the Shortcuts section of
/// the General pane. Give it a fixed frame at the call site so the row does not
/// jump as the title changes length.
struct ShortcutRecorder: NSViewRepresentable {

    let action: HotkeyAction
    let combo: KeyCombo?
    /// Returns a rejection to display, or nil when the combination was accepted.
    let onRecord: (KeyCombo) -> HotkeyRejection?
    let onClear: () -> Void

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.rowLabel = action.title
        button.combo = combo
        button.onRecord = onRecord
        button.onClear = onClear
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.rowLabel = action.title
        button.onRecord = onRecord
        button.onClear = onClear
        // Do not stomp the live preview mid-recording.
        if !button.isRecording, button.combo != combo {
            button.combo = combo
        }
    }
}
