import AppKit
import CSQLite
import ImageIO
import XCTest
@testable import Clipp

final class ClipboardModelTests: XCTestCase {
    @MainActor
    func testTextCaptureIgnoresRecopiesPausedAndConcealedContent() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            pasteboard.releaseGlobally()
            try? FileManager.default.removeItem(at: directory)
        }
        func write(_ text: String) {
            pasteboard.clearContents()
            XCTAssertTrue(pasteboard.setString(text, forType: .string))
        }

        write("Before launch")
        let model = ClipboardModel(pasteboard: pasteboard, directory: directory)
        let store = try XCTUnwrap(model.store)
        await model.poll()
        XCTAssertTrue(model.entries.isEmpty)

        let copiedAt = Date()
        write("Olá, clipboard! 📝")
        await model.poll()
        let entry = try XCTUnwrap(model.entries.first)
        XCTAssertEqual(model.total, 1)
        XCTAssertEqual(entry.kind, .text)
        XCTAssertEqual(entry.text, "Olá, clipboard! 📝")
        XCTAssertGreaterThanOrEqual(entry.createdAt, copiedAt)
        XCTAssertLessThanOrEqual(entry.createdAt, Date())
        let saved = try await store.content(id: entry.id)
        XCTAssertEqual(saved?.text, entry.text)

        await model.poll()
        let change = await model.copy(entry)
        XCTAssertEqual(change, pasteboard.changeCount)
        XCTAssertEqual(pasteboard.string(forType: .string), entry.text)
        await model.poll()
        XCTAssertEqual(model.total, 1)

        model.togglePause()
        write("While paused")
        await model.poll()
        write("Immediately before resuming")
        model.togglePause()
        await model.poll()
        XCTAssertEqual(model.total, 1)

        write("Secret")
        XCTAssertTrue(pasteboard.setData(Data(), forType: .init("org.nspasteboard.ConcealedType")))
        await model.poll()
        XCTAssertEqual(model.total, 1)

        write("After resuming")
        await model.poll()
        XCTAssertEqual(model.entries.map(\.text), ["After resuming", entry.text])
        let count = try await store.count()
        XCTAssertEqual(count, 2)
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testBatchCapturePersistsImageAndRecopiesOriginalBytes() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            pasteboard.releaseGlobally()
            try? FileManager.default.removeItem(at: directory)
        }
        let model = ClipboardModel(pasteboard: pasteboard, directory: directory)
        let store = try XCTUnwrap(model.store)
        // A valid one-pixel opaque red RGBA PNG, including CRCs.
        let png = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg=="))
        let imageItem = NSPasteboardItem()
        XCTAssertTrue(imageItem.setData(png, forType: .png))
        let textItem = NSPasteboardItem()
        XCTAssertTrue(textItem.setString("Alongside the image", forType: .string))
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([imageItem, textItem]))
        await model.poll()

        XCTAssertEqual(model.total, 2)
        XCTAssertEqual(model.entries.count, 2)
        XCTAssertEqual(model.entries.first?.text, "Alongside the image")
        let image = try XCTUnwrap(model.entries.first { $0.kind == .image })
        XCTAssertEqual(image.byteCount, png.count)
        let thumbnail = try XCTUnwrap(image.thumbnail)
        XCTAssertNotNil(NSImage(data: thumbnail))
        let saved = try await store.content(id: image.id)
        XCTAssertEqual(saved?.imageData, png)

        let imageChange = await model.copy(image)
        XCTAssertEqual(imageChange, pasteboard.changeCount)
        XCTAssertEqual(pasteboard.data(forType: .png), png)
        await model.poll()
        XCTAssertEqual(model.total, 2)
        XCTAssertNil(model.errorMessage)

        let reopened = ClipboardModel(pasteboard: pasteboard, directory: directory)
        await reopened.reload()
        XCTAssertEqual(reopened.total, 2)
        XCTAssertEqual(reopened.entries.map(\.id), model.entries.map(\.id))
        XCTAssertEqual(reopened.entries.first { $0.kind == .image }?.thumbnail, thumbnail)
        XCTAssertNil(reopened.errorMessage)

        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let pixels = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let jpegBytes = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(jpegBytes, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, pixels, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let jpeg = jpegBytes as Data
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setData(jpeg, forType: .init("public.jpeg")))
        await model.poll()
        XCTAssertEqual(model.total, 3)
        let jpegEntry = try XCTUnwrap(model.entries.first)
        XCTAssertEqual(jpegEntry.kind, .image)
        let jpegContent = try await store.content(id: jpegEntry.id)
        XCTAssertEqual(jpegContent?.imageData, jpeg)
        XCTAssertNotNil(jpegEntry.thumbnail.flatMap(NSImage.init(data:)))
        let jpegChange = await model.copy(jpegEntry)
        XCTAssertEqual(jpegChange, pasteboard.changeCount)
        XCTAssertEqual(pasteboard.data(forType: .init("public.jpeg")), jpeg)
        await model.poll()
        XCTAssertEqual(model.total, 3)
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testCopyOfDeletedEntryPreservesPasteboard() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            pasteboard.releaseGlobally()
            try? FileManager.default.removeItem(at: directory)
        }
        let model = ClipboardModel(pasteboard: pasteboard, directory: directory)
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("Saved item", forType: .string))
        await model.poll()
        let entry = try XCTUnwrap(model.entries.first)
        await model.delete(entry)

        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("Keep this", forType: .string))
        let change = pasteboard.changeCount
        let receipt = await model.copy(entry)
        XCTAssertNil(receipt)
        XCTAssertEqual(pasteboard.changeCount, change)
        XCTAssertEqual(pasteboard.string(forType: .string), "Keep this")
        XCTAssertEqual(model.total, 0)
    }

    @MainActor
    func testFailedDatabaseWriteRetriesWithoutLosingNextCopy() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            pasteboard.releaseGlobally()
            try? FileManager.default.removeItem(at: directory)
        }
        let model = ClipboardModel(pasteboard: pasteboard, directory: directory)
        let store = try XCTUnwrap(model.store)
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(directory.appendingPathComponent("history.sqlite3").path, &connection), SQLITE_OK)
        let lock = try XCTUnwrap(connection)
        defer { sqlite3_close(lock) }
        XCTAssertEqual(sqlite3_exec(lock, "BEGIN IMMEDIATE", nil, nil, nil), SQLITE_OK)

        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("pendente", forType: .string))
        await model.poll()
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.total, 0)
        let blockedCount = try await store.count()
        XCTAssertEqual(blockedCount, 0)

        XCTAssertEqual(sqlite3_exec(lock, "COMMIT", nil, nil, nil), SQLITE_OK)
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("seguinte", forType: .string))
        await model.poll()
        XCTAssertEqual(model.entries.map(\.text), ["seguinte", "pendente"])
        XCTAssertEqual(model.total, 2)
        await model.poll()
        let recoveredCount = try await store.count()
        XCTAssertEqual(recoveredCount, 2)
    }
}
