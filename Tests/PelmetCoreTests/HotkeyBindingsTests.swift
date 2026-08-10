import Foundation
import Testing
@testable import PelmetCore

struct HotkeyBindingsTests {

    private let toggleDefault = HotkeyAction.toggle.defaultCombo
    private let shelfDefault = HotkeyAction.shelf.defaultCombo
    private let custom = KeyCombo(keyCode: 38, modifiers: [.option, .command])  // ⌥⌘J

    @Test func testDefaultsMatchTheShippedCombos() {
        #expect(HotkeyBindings.defaults.toggle == toggleDefault)
        #expect(HotkeyBindings.defaults.shelf == shelfDefault)
    }

    @Test func testEventIDsAreFrozenAtThePreRecorderValues() {
        #expect(HotkeyAction.toggle.eventID == 1)
        #expect(HotkeyAction.shelf.eventID == 2)
    }

    @Test func testSubscriptGetsAndSets() {
        var bindings = HotkeyBindings.defaults
        #expect(bindings[.toggle] == toggleDefault)
        #expect(bindings[.shelf] == shelfDefault)
        bindings[.toggle] = custom
        #expect(bindings.toggle == custom)
        bindings[.shelf] = nil
        #expect(bindings.shelf == nil)
    }

    @Test func testConflictingActionFindsTheOtherAction() {
        let bindings = HotkeyBindings.defaults
        #expect(bindings.conflictingAction(with: shelfDefault, assigningTo: .toggle) == .shelf)
        #expect(bindings.conflictingAction(with: toggleDefault, assigningTo: .shelf) == .toggle)
    }

    @Test func testReRecordingAnActionsOwnShortcutIsNotAConflict() {
        let bindings = HotkeyBindings.defaults
        #expect(bindings.conflictingAction(with: toggleDefault, assigningTo: .toggle) == nil)
    }

    @Test func testAClearedActionNeverConflicts() {
        let bindings = HotkeyBindings(toggle: nil, shelf: nil)
        #expect(bindings.conflictingAction(with: toggleDefault, assigningTo: .toggle) == nil)
        #expect(bindings.conflictingAction(with: custom, assigningTo: .shelf) == nil)
    }

    @Test func testAbsentRecordResolvesToTheShippedDefault() {
        #expect(HotkeyBindingResolver.resolve(nil, for: .toggle) == toggleDefault)
        #expect(HotkeyBindingResolver.resolve(nil, for: .shelf) == shelfDefault)
    }

    @Test func testRecordWithoutAKeyCodeResolvesToCleared() {
        let cleared = HotkeyRecord(combo: nil)
        #expect(HotkeyBindingResolver.resolve(cleared, for: .toggle) == nil)
    }

    @Test func testClearedRecordSurvivesAJSONRoundTrip() throws {
        // The distinction that matters: a cleared shortcut must not decode back
        // into the default, or clearing would silently undo itself at launch.
        let data = try JSONEncoder().encode(HotkeyRecord(combo: nil))
        let decoded = try JSONDecoder().decode(HotkeyRecord.self, from: data)
        #expect(decoded.combo == nil)
        #expect(HotkeyBindingResolver.resolve(decoded, for: .toggle) == nil)
    }

    @Test func testCustomRecordSurvivesAJSONRoundTrip() throws {
        let data = try JSONEncoder().encode(HotkeyRecord(combo: custom))
        let decoded = try JSONDecoder().decode(HotkeyRecord.self, from: data)
        #expect(decoded.combo == custom)
        #expect(HotkeyBindingResolver.resolve(decoded, for: .toggle) == custom)
    }

    @Test func testImplausibleKeycodeResolvesToTheDefault() {
        let modifierKey = HotkeyRecord(combo: KeyCombo(keyCode: 55, modifiers: [.command]))
        #expect(HotkeyBindingResolver.resolve(modifierKey, for: .toggle) == toggleDefault)
        let outOfRange = HotkeyRecord(combo: KeyCombo(keyCode: 300, modifiers: [.command]))
        #expect(HotkeyBindingResolver.resolve(outOfRange, for: .shelf) == shelfDefault)
    }

    @Test func testResolveBuildsBothBindings() {
        let bindings = HotkeyBindingResolver.resolve(
            toggle: HotkeyRecord(combo: custom),
            shelf: HotkeyRecord(combo: nil)
        )
        #expect(bindings.toggle == custom)
        #expect(bindings.shelf == nil)
    }

    @Test func testResolveWithNoStoredRecordsIsTheShippedDefault() {
        #expect(HotkeyBindingResolver.resolve(toggle: nil, shelf: nil) == .defaults)
    }
}
