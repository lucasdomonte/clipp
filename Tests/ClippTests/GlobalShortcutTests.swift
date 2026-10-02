import Carbon
import XCTest
@testable import Clipp

final class GlobalShortcutTests: XCTestCase {
    @MainActor
    func testDefaultSavedAndRemovedShortcutWithoutRegisteringGlobalEvents() throws {
        let suite = "ClippTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = GlobalShortcut(defaults: defaults, enabled: false)
        XCTAssertEqual(model.displayName, "⇧⌘V")
        model.start()
        model.beginRecording()
        XCTAssertFalse(model.isRecording)
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(defaults.object(forKey: "historyShortcut"))

        defaults.set(["enabled": true, "keyCode": kVK_ANSI_J,
                      "modifiers": controlKey | optionKey, "key": "J"], forKey: "historyShortcut")
        let saved = GlobalShortcut(defaults: defaults, enabled: false)
        XCTAssertEqual(saved.displayName, "⌃⌥J")
        saved.clear()
        saved.start()
        saved.cancelRecording()
        XCTAssertEqual(saved.displayName, "Não definido")
        XCTAssertEqual(GlobalShortcut(defaults: defaults, enabled: false).displayName, "Não definido")

        defaults.set(["enabled": true, "keyCode": -1,
                      "modifiers": cmdKey, "key": "?"], forKey: "historyShortcut")
        XCTAssertEqual(GlobalShortcut(defaults: defaults, enabled: false).displayName, "⇧⌘V")
    }

    @MainActor
    func testValidationProtectsTypingAndCommonShortcuts() {
        for modifiers in [0, shiftKey, optionKey, shiftKey | optionKey] {
            XCTAssertNotNil(GlobalShortcut.validationMessage(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(modifiers)))
        }
        for keyCode in [kVK_ANSI_C, kVK_ANSI_V, kVK_ANSI_X, kVK_ANSI_Q, kVK_Tab, kVK_Space] {
            XCTAssertNotNil(GlobalShortcut.validationMessage(keyCode: UInt32(keyCode), modifiers: UInt32(cmdKey)))
        }
        XCTAssertNotNil(GlobalShortcut.validationMessage(keyCode: UInt32(kVK_ANSI_Q), modifiers: UInt32(cmdKey | shiftKey)))
        XCTAssertNotNil(GlobalShortcut.validationMessage(keyCode: 128, modifiers: UInt32(cmdKey)))
        XCTAssertNotNil(GlobalShortcut.validationMessage(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(cmdKey | alphaLock)))
        XCTAssertNil(GlobalShortcut.validationMessage(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey)))
        XCTAssertNil(GlobalShortcut.validationMessage(keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(controlKey | optionKey)))
    }
}
