import Foundation
import Testing
@testable import PelmetCore

struct KeyComboTests {

    private let toggleDefault = HotkeyAction.toggle.defaultCombo

    @Test func testDisplayStringUsesMacOSModifierOrder() {
        // Built out of order on purpose: display must not echo the literal.
        let combo = KeyCombo(keyCode: 11, modifiers: [.command, .shift, .option, .control])
        #expect(combo.displayString() == "⌃⌥⇧⌘B")
    }

    @Test func testShippedDefaultsRenderAsTheyAlwaysHave() {
        #expect(HotkeyAction.toggle.defaultCombo.displayString() == "⌥⌘B")
        #expect(HotkeyAction.shelf.defaultCombo.displayString() == "⌥⌘N")
    }

    @Test func testInjectedKeyNameOverridesTheAnsiTable() {
        // The Dvorak path: the same position prints a different character.
        #expect(toggleDefault.displayString(keyName: "X") == "⌥⌘X")
    }

    @Test func testSpecialKeyNameWinsOverAnInjectedName() {
        // UCKeyTranslate returns junk for arrows, so the special table must win.
        let leftArrow = KeyCombo(keyCode: 123, modifiers: [.control])
        #expect(leftArrow.displayString(keyName: "Z") == "⌃←")
    }

    @Test func testAccessibilityDescriptionSpellsOutModifiers() {
        #expect(toggleDefault.accessibilityDescription() == "Option Command B")
        let pageDown = KeyCombo(keyCode: 121, modifiers: [.control, .shift])
        #expect(pageDown.accessibilityDescription() == "Control Shift Page Down")
    }

    @Test func testEverySpecialKeyHasADisplayAndSpokenName() {
        let specialKeyCodes: [UInt16] = [
            36, 48, 49, 51, 53, 71, 76, 114, 115, 116, 117, 119, 121, 123, 124, 125, 126,
            122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79,
            80, 90,
        ]
        for keyCode in specialKeyCodes {
            #expect(KeyCodeNames.specialName(for: keyCode) != nil)
            #expect(KeyCodeNames.specialSpokenName(for: keyCode) != nil)
        }
    }

    @Test func testSpecialKeyGlyphs() {
        #expect(KeyCodeNames.specialName(for: 36) == "↩")
        #expect(KeyCodeNames.specialName(for: 48) == "⇥")
        #expect(KeyCodeNames.specialName(for: 49) == "Space")
        #expect(KeyCodeNames.specialName(for: 51) == "⌫")
        #expect(KeyCodeNames.specialName(for: 117) == "⌦")
        #expect(KeyCodeNames.specialName(for: 53) == "⎋")
        #expect(KeyCodeNames.specialName(for: 123) == "←")
        #expect(KeyCodeNames.specialName(for: 124) == "→")
        #expect(KeyCodeNames.specialName(for: 125) == "↓")
        #expect(KeyCodeNames.specialName(for: 126) == "↑")
        #expect(KeyCodeNames.specialName(for: 115) == "↖")
        #expect(KeyCodeNames.specialName(for: 119) == "↘")
        #expect(KeyCodeNames.specialName(for: 116) == "⇞")
        #expect(KeyCodeNames.specialName(for: 121) == "⇟")
        #expect(KeyCodeNames.specialName(for: 122) == "F1")
        #expect(KeyCodeNames.specialName(for: 90) == "F20")
    }

    @Test func testAnsiTableCoversLettersDigitsAndPunctuation() {
        #expect(KeyCodeNames.ansiName(for: 11) == "B")
        #expect(KeyCodeNames.ansiName(for: 45) == "N")
        #expect(KeyCodeNames.ansiName(for: 0) == "A")
        #expect(KeyCodeNames.ansiName(for: 29) == "0")
        #expect(KeyCodeNames.ansiName(for: 23) == "5")
        #expect(KeyCodeNames.ansiName(for: 43) == ",")
        #expect(KeyCodeNames.ansiName(for: 50) == "`")
    }

    @Test func testUnknownKeycodeIsNamedNumerically() {
        let unknown = KeyCombo(keyCode: 127, modifiers: [.option, .command])
        #expect(KeyCodeNames.displayName(for: 127) == nil)
        #expect(unknown.displayString() == "⌥⌘Key 127")
    }

    @Test func testCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(toggleDefault)
        let decoded = try JSONDecoder().decode(KeyCombo.self, from: data)
        #expect(decoded == toggleDefault)
    }

    @Test func testModifiersEncodeAsABareNumber() throws {
        let data = try JSONEncoder().encode(toggleDefault)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"modifiers\":10"))
    }

    @Test func testUnknownModifierBitsAreMaskedOnDecode() throws {
        let json = Data(#"{"keyCode":11,"modifiers":255}"#.utf8)
        let decoded = try JSONDecoder().decode(KeyCombo.self, from: json)
        #expect(decoded.modifiers == .all)
    }

    @Test func testUnknownJSONKeyIsIgnored() throws {
        let json = Data(#"{"keyCode":11,"modifiers":10,"future":1}"#.utf8)
        let decoded = try JSONDecoder().decode(KeyCombo.self, from: json)
        #expect(decoded == toggleDefault)
    }

    @Test func testIsPrintableClassification() {
        #expect(KeyCodeNames.isPrintable(11))  // B
        #expect(KeyCodeNames.isPrintable(18))  // 1
        #expect(KeyCodeNames.isPrintable(43))  // comma
        #expect(KeyCodeNames.isPrintable(49))  // Space
        #expect(KeyCodeNames.isPrintable(36))  // Return
        #expect(KeyCodeNames.isPrintable(51))  // Delete
        #expect(!KeyCodeNames.isPrintable(96))  // F5
        #expect(!KeyCodeNames.isPrintable(123))  // Left arrow
        #expect(!KeyCodeNames.isPrintable(115))  // Home
        #expect(!KeyCodeNames.isPrintable(53))  // Escape
        #expect(!KeyCodeNames.isPrintable(55))  // Command
    }

    @Test func testModifierKeysAndOutOfRangeKeysAreNotPlausible() {
        #expect(!KeyCombo(keyCode: 55, modifiers: [.command]).isPlausible)
        #expect(!KeyCombo(keyCode: 57, modifiers: [.command]).isPlausible)
        #expect(!KeyCombo(keyCode: 200, modifiers: [.command]).isPlausible)
        #expect(toggleDefault.isPlausible)
    }

    @Test func testInitDropsBitsOutsideTheKnownModifiers() {
        let combo = KeyCombo(keyCode: 11, modifiers: KeyModifiers(rawValue: 0xFF))
        #expect(combo.modifiers == .all)
    }
}
