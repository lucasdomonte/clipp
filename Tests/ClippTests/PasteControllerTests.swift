import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Clipp

final class PasteControllerTests: XCTestCase {
    @MainActor
    func testPasteShortcutIsCommandVWithoutOtherModifiers() throws {
        let events = try XCTUnwrap(PasteController.makePasteEvents())
        XCTAssertEqual(events.map(\.type), [.keyDown, .keyUp])
        for event in events {
            XCTAssertEqual(event.flags, .maskCommand)
            XCTAssertEqual(event.getIntegerValueField(.keyboardEventKeycode), Int64(kVK_ANSI_V))
        }
    }

    @MainActor
    func testPasteRejectsOwnApplicationWithoutChangingClipboardOrRequestingPermission() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Item preservado", forType: .string)
        let changeCount = pasteboard.changeCount
        let error = await PasteController.paste(into: .current, expectedChangeCount: changeCount, pasteboard: pasteboard)
        XCTAssertNotNil(error)
        XCTAssertEqual(pasteboard.changeCount, changeCount)
        XCTAssertEqual(pasteboard.string(forType: .string), "Item preservado")
    }
}
