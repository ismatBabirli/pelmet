import Testing
@testable import PelmetCore

struct HotkeyValidatorTests {

    private let bindings = HotkeyBindings.defaults

    private func validate(
        _ combo: KeyCombo,
        for action: HotkeyAction = .toggle,
        reserved: [ReservedCombo] = HotkeyValidator.systemReserved
    ) -> HotkeyRejection? {
        HotkeyValidator.validate(
            combo, for: action, against: bindings, systemReserved: reserved
        )
    }

    /// The regression that matters most: whatever the rules are, the shortcuts
    /// Pelmet has always shipped have to remain legal.
    @Test func testShippedDefaultsPassTheirOwnValidator() {
        #expect(validate(HotkeyAction.toggle.defaultCombo, for: .toggle) == nil)
        #expect(validate(HotkeyAction.shelf.defaultCombo, for: .shelf) == nil)
    }

    @Test func testBareKeyIsRejected() {
        #expect(validate(KeyCombo(keyCode: 11, modifiers: [])) == .noPrimaryModifier)
    }

    @Test func testShiftOnlyIsRejected() {
        #expect(validate(KeyCombo(keyCode: 11, modifiers: [.shift])) == .noPrimaryModifier)
    }

    @Test func testSingleModifierOnACharacterKeyIsRejected() {
        // ⌘B, ⌥B and ⌃B would each take that combination away from every app.
        #expect(validate(KeyCombo(keyCode: 11, modifiers: [.command])) == .needsSecondModifier)
        #expect(validate(KeyCombo(keyCode: 11, modifiers: [.option])) == .needsSecondModifier)
        #expect(validate(KeyCombo(keyCode: 11, modifiers: [.control])) == .needsSecondModifier)
    }

    @Test func testSingleModifierOnAPositionalKeyIsAccepted() {
        #expect(validate(KeyCombo(keyCode: 96, modifiers: [.command])) == nil)  // ⌘F5
        #expect(validate(KeyCombo(keyCode: 126, modifiers: [.option])) == nil)  // ⌥↑
        #expect(validate(KeyCombo(keyCode: 53, modifiers: [.command])) == nil)  // ⌘⎋
    }

    @Test func testTwoModifiersOnACharacterKeyIsAccepted() {
        #expect(validate(KeyCombo(keyCode: 11, modifiers: [.shift, .command])) == nil)
        #expect(validate(KeyCombo(keyCode: 11, modifiers: [.control, .option])) == nil)
        #expect(validate(KeyCombo(keyCode: 49, modifiers: [.option, .command])) == nil)  // ⌥⌘Space
    }

    @Test func testModifierKeyOnItsOwnIsRejected() {
        #expect(validate(KeyCombo(keyCode: 55, modifiers: [.command])) == .modifiersOnly)
        #expect(validate(KeyCombo(keyCode: 63, modifiers: [.control])) == .modifiersOnly)
    }

    @Test func testOutOfRangeKeycodeIsRejected() {
        #expect(validate(KeyCombo(keyCode: 300, modifiers: [.option, .command])) == .unsupportedKey)
    }

    @Test func testSystemReservedCombosAreNamed() {
        let cases: [(KeyCombo, String)] = [
            (KeyCombo(keyCode: 49, modifiers: [.command]), "Spotlight"),
            (KeyCombo(keyCode: 49, modifiers: [.control, .command]), "Emoji & Symbols"),
            (KeyCombo(keyCode: 49, modifiers: [.control]), "The input source switcher"),
            (KeyCombo(keyCode: 49, modifiers: [.control, .option]), "The input source switcher"),
            (KeyCombo(keyCode: 48, modifiers: [.command]), "The app switcher"),
            (KeyCombo(keyCode: 48, modifiers: [.shift, .command]), "The app switcher"),
            (KeyCombo(keyCode: 50, modifiers: [.command]), "The window switcher"),
            (KeyCombo(keyCode: 50, modifiers: [.shift, .command]), "The window switcher"),
            (KeyCombo(keyCode: 53, modifiers: [.option, .command]), "Force Quit"),
            (KeyCombo(keyCode: 12, modifiers: [.control, .command]), "Lock Screen"),
            (KeyCombo(keyCode: 3, modifiers: [.control, .command]), "Enter Full Screen"),
            (KeyCombo(keyCode: 20, modifiers: [.shift, .command]), "Screenshot"),
            (KeyCombo(keyCode: 21, modifiers: [.shift, .command]), "Screenshot"),
            (KeyCombo(keyCode: 23, modifiers: [.shift, .command]), "Screenshot"),
            (KeyCombo(keyCode: 126, modifiers: [.control]), "Mission Control"),
            (KeyCombo(keyCode: 125, modifiers: [.control]), "App Exposé"),
            (KeyCombo(keyCode: 123, modifiers: [.control]), "Switching Spaces"),
            (KeyCombo(keyCode: 124, modifiers: [.control]), "Switching Spaces"),
            (KeyCombo(keyCode: 2, modifiers: [.option, .command]), "The Dock"),
        ]
        for (combo, owner) in cases {
            #expect(validate(combo) == .systemReserved(owner: owner))
        }
    }

    /// ⌘Space fails the two-modifier rule too, but naming Spotlight is a far
    /// better sentence, so reserved has to be checked first.
    @Test func testReservedIsCheckedBeforeTheModifierRules() {
        #expect(validate(KeyCombo(keyCode: 49, modifiers: [.command]))
            == .systemReserved(owner: "Spotlight"))
    }

    /// The seam the live CopySymbolicHotKeys read plugs into.
    @Test func testInjectedReservedListIsHonored() {
        let injected = [ReservedCombo(combo: HotkeyAction.toggle.defaultCombo, owner: "Test App")]
        #expect(validate(HotkeyAction.toggle.defaultCombo, reserved: injected)
            == .systemReserved(owner: "Test App"))
    }

    @Test func testDuplicateAcrossActionsIsRejected() {
        #expect(validate(HotkeyAction.shelf.defaultCombo, for: .toggle)
            == .alreadyAssigned(.shelf))
        #expect(validate(HotkeyAction.toggle.defaultCombo, for: .shelf)
            == .alreadyAssigned(.toggle))
    }

    @Test func testEveryRejectionProducesANonEmptySentence() {
        let combo = KeyCombo(keyCode: 11, modifiers: [.command])
        let rejections: [HotkeyRejection] = [
            .modifiersOnly,
            .noPrimaryModifier,
            .needsSecondModifier,
            .systemReserved(owner: "Spotlight"),
            .alreadyAssigned(.shelf),
            .unsupportedKey,
        ]
        for rejection in rejections {
            #expect(!rejection.message(for: combo).isEmpty)
        }
    }

    @Test func testRejectionSentencesNameWhatWentWrong() {
        let combo = KeyCombo(keyCode: 11, modifiers: [.command])
        #expect(HotkeyRejection.needsSecondModifier.message(for: combo).contains("⌘B"))
        #expect(HotkeyRejection.systemReserved(owner: "Spotlight")
            .message(for: combo).contains("Spotlight"))
        #expect(HotkeyRejection.alreadyAssigned(.shelf)
            .message(for: combo).contains(HotkeyAction.shelf.title))
    }

    @Test func testRejectionSentenceUsesTheLiveKeyName() {
        let combo = KeyCombo(keyCode: 11, modifiers: [.command])
        #expect(HotkeyRejection.needsSecondModifier
            .message(for: combo, keyName: "X").contains("⌘X"))
    }
}
