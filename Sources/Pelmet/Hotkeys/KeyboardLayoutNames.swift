import Carbon.HIToolbox
import Foundation
import PelmetCore

/// Names the character the user's *live* keyboard layout prints for a physical
/// key position.
///
/// This is a correctness concern, not polish. A Carbon hotkey is bound to a
/// position, so on Dvorak the key that reports `kVK_ANSI_B` is the one labelled
/// X. Showing that user "⌥⌘B" names a key they do not have. The binding itself is
/// unaffected by a layout change: the same physical key keeps firing, and only
/// its label moves.
final class KeyboardLayoutNames {

    static let shared = KeyboardLayoutNames()

    /// Bumped every time the input source changes, so views that cached a label
    /// know to re-render.
    private(set) var generation = 0

    private var cache: [UInt16: String] = [:]
    private let lock = NSLock()

    private init() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourceChanged),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil
        )
    }

    /// nil when the current input source carries no `kTISPropertyUnicodeKeyLayoutData`
    /// (true of IMEs such as Japanese and Pinyin) or translation produced nothing.
    /// Callers fall back to `KeyCodeNames.ansiName`.
    func characterName(for keyCode: UInt16) -> String? {
        lock.lock()
        if let cached = cache[keyCode] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let translated = translate(keyCode) else { return nil }
        lock.lock()
        cache[keyCode] = translated
        lock.unlock()
        return translated
    }

    @objc private func inputSourceChanged() {
        lock.lock()
        cache.removeAll()
        generation += 1
        lock.unlock()
        // Tooltips, the right-click menu and the Settings pane all quote a
        // shortcut, so they relabel without waiting for a relaunch.
        NotificationCenter.default.post(name: .pelmetHotkeyBindingsDidChange, object: nil)
    }

    private func translate(_ keyCode: UInt16) -> String? {
        guard let layoutData = currentLayoutData() else { return nil }

        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)

        let status = layoutData.withUnsafeBytes { rawBuffer -> OSStatus in
            guard let base = rawBuffer.baseAddress else { return OSStatus(paramErr) }
            let layout = base.assumingMemoryBound(to: UCKeyboardLayout.self)
            // Zero modifier state on purpose: ⌥B should read "⌥B", not "⌥∫".
            return UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
        }

        guard status == noErr, length > 0 else { return nil }
        let name = String(utf16CodeUnits: characters, count: length)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        return name.isEmpty ? nil : name
    }

    private func currentLayoutData() -> Data? {
        if let data = layoutData(from: TISCopyCurrentKeyboardLayoutInputSource()) { return data }
        // An IME (Japanese, Pinyin) exposes no Unicode layout data of its own, so
        // fall back to the ASCII-capable source macOS pairs with it.
        return layoutData(from: TISCopyCurrentASCIICapableKeyboardLayoutInputSource())
    }

    /// The TIS "Copy" functions hand back a +1 reference, hence `takeRetainedValue`.
    private func layoutData(from source: Unmanaged<TISInputSource>?) -> Data? {
        guard let source else { return nil }
        let inputSource = source.takeRetainedValue()
        guard let pointer = TISGetInputSourceProperty(
            inputSource, kTISPropertyUnicodeKeyLayoutData
        ) else { return nil }
        return Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
    }
}
