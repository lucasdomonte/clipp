import Foundation
import XCTest
@testable import Clipp

final class ClipboardStoreTests: XCTestCase {
    func testCursorPagesRemainStableAfterNewCopiesAndDeletion() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ClipboardStore(directory: directory)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0...6 {
            try await store.insert(ClipboardContent(kind: .text, text: index == 1 ? "Outro" : "Alvo \(index)"),
                                   sourceApp: nil, createdAt: date.addingTimeInterval(Double(index / 3)))
        }
        let first = try await store.fetch(limit: 2)
        XCTAssertEqual(first.map(\.text), ["Alvo 6", "Alvo 5"])
        try await store.insert(ClipboardContent(kind: .text, text: "Alvo novo"),
                               sourceApp: nil, createdAt: date.addingTimeInterval(10))
        try await store.delete(id: first[0].id)
        let second = try await store.fetch(limit: 2, before: first.last)
        XCTAssertEqual(second.map(\.text), ["Alvo 4", "Alvo 3"])
        let third = try await store.fetch(limit: 2, before: second.last)
        XCTAssertEqual(third.map(\.text), ["Alvo 2", "Outro"])
        let fourth = try await store.fetch(limit: 2, before: third.last)
        XCTAssertEqual(fourth.map(\.text), ["Alvo 0"])
        let end = try await store.fetch(limit: 2, before: fourth.last)
        XCTAssertTrue(end.isEmpty)
        let matches = try await store.fetch(query: "alvo", limit: 10, before: second.last)
        XCTAssertEqual(matches.map(\.text), ["Alvo 2", "Alvo 0"])
    }

    func testHistoryRoundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var store: ClipboardStore? = try ClipboardStore(directory: directory)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let text = "Olá 👨‍👩‍👧‍👦, '100%'_\0" + String(repeating: "á", count: 1_200)
        try await store!.insert(ClipboardContent(kind: .text, text: text), sourceApp: "Teste", createdAt: date)
        let image = Data([0, 1, 255, 2])
        let thumbnail = Data([8, 9])
        try await store!.insert(ClipboardContent(kind: .image, imageData: image, thumbnail: thumbnail),
                                sourceApp: nil, createdAt: date)
        try await store!.insert(ClipboardContent(kind: .text, text: "Mais recente"),
                                sourceApp: nil, createdAt: date.addingTimeInterval(1))

        let entries = try await store!.fetch()
        XCTAssertEqual(entries.map(\.kind), [.text, .image, .text])
        XCTAssertEqual(entries[2].text, String(text.prefix(1_000)))
        XCTAssertEqual(entries[2].byteCount, text.utf8.count)
        XCTAssertEqual(entries[2].sourceApp, "Teste")
        XCTAssertEqual(entries[2].createdAt, date)
        XCTAssertEqual(entries[1].thumbnail, thumbnail)
        let restoredText = try await store!.content(id: entries[2].id)
        let restoredImage = try await store!.content(id: entries[1].id)
        XCTAssertEqual(restoredText?.text, text)
        XCTAssertEqual(restoredImage?.imageData, image)
        let matches = try await store!.fetch(query: "'100%'_")
        XCTAssertEqual(matches.map(\.id), [entries[2].id])
        let noMatches = try await store!.fetch(query: "' OR 1=1 --")
        XCTAssertTrue(noMatches.isEmpty)
        let page = try await store!.fetch(limit: 1, before: entries[0])
        XCTAssertEqual(page.map(\.id), [entries[1].id])
        for limit in [0, -1] {
            do {
                _ = try await store!.fetch(limit: limit)
                XCTFail("A non-positive page size must be rejected")
            } catch { }
        }

        do {
            try await store!.insert(ClipboardContent(kind: .text, imageData: image), sourceApp: nil)
            XCTFail("Invalid content must be rejected")
        } catch { }
        store = nil
        let reopened = try ClipboardStore(directory: directory)
        let initialCount = try await reopened.count()
        XCTAssertEqual(initialCount, 3)
        let persistedImage = try await reopened.content(id: entries[1].id)
        XCTAssertEqual(persistedImage?.imageData, image)
        try await reopened.delete(id: entries[1].id)
        let finalCount = try await reopened.count()
        let deleted = try await reopened.content(id: entries[1].id)
        XCTAssertEqual(finalCount, 2)
        XCTAssertNil(deleted)
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("history.sqlite3").path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
}
