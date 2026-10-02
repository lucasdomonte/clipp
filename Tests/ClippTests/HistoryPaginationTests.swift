import AppKit
import XCTest
@testable import Clipp

final class HistoryPaginationTests: XCTestCase {
    @MainActor
    func testPagesAppendOnceRemainStableAfterDatabaseChangesAndResetOnReload() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "ClippTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            pasteboard.releaseGlobally()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let model = ClipboardModel(pasteboard: pasteboard, directory: directory, defaults: defaults)
        model.isHistoryVisible = true
        let store = try XCTUnwrap(model.store)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<75 {
            try await store.insert(ClipboardContent(kind: .text, text: "Item \(index)"),
                                   sourceApp: nil, createdAt: date)
        }
        let original = try await store.fetch(limit: 75)
        await model.reload()
        XCTAssertEqual(model.entries.map(\.id), original.prefix(30).map(\.id))
        XCTAssertTrue(model.hasMore)
        XCTAssertEqual(model.total, 75)

        // Rows added or removed before the cursor must not shift the next page.
        try await store.insert(ClipboardContent(kind: .text, text: "Nova cópia"),
                               sourceApp: nil, createdAt: date.addingTimeInterval(1))
        try await store.delete(id: original[0].id)
        async let first: Void = model.loadMore()
        async let duplicate: Void = model.loadMore()
        _ = await (first, duplicate)
        XCTAssertEqual(model.entries.map(\.id), original.prefix(60).map(\.id))
        XCTAssertEqual(Set(model.entries.map(\.id)).count, 60)
        XCTAssertTrue(model.hasMore)

        await model.loadMore()
        XCTAssertEqual(model.entries.map(\.id), original.map(\.id))
        XCTAssertFalse(model.hasMore)
        await model.loadMore()
        XCTAssertEqual(model.entries.count, 75)
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.isLoadingMore)
        XCTAssertNil(model.paginationError)

        await model.reload()
        let current = try await store.fetch(limit: 30)
        XCTAssertEqual(model.entries.map(\.id), current.map(\.id))
        XCTAssertEqual(model.entries.first?.text, "Nova cópia")
        XCTAssertTrue(model.hasMore)

        model.isHistoryVisible = false
        XCTAssertTrue(model.entries.isEmpty)
        XCTAssertEqual(model.total, 75)
        XCTAssertFalse(model.hasMore)
        XCTAssertFalse(model.isLoadingMore)
        model.isHistoryVisible = true
        await model.reload()
        XCTAssertEqual(model.entries.map(\.id), current.map(\.id))
        XCTAssertEqual(model.entries.count, 30)
        XCTAssertTrue(model.hasMore)
    }

    @MainActor
    func testNearEndLoadsOnlyMatchingNextPageAndChangingSearchResetsCursor() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "ClippTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            pasteboard.releaseGlobally()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let model = ClipboardModel(pasteboard: pasteboard, directory: directory, defaults: defaults)
        let store = try XCTUnwrap(model.store)
        for index in 0..<90 {
            let text = index.isMultiple(of: 3) ? "Outro \(index)" : "Alvo \(index)"
            try await store.insert(ClipboardContent(kind: .text, text: text), sourceApp: nil)
        }

        model.query = "alvo"
        await model.reload()
        let matches = try await store.fetch(query: "alvo", limit: 90)
        XCTAssertEqual(matches.count, 60)
        XCTAssertEqual(model.entries.map(\.id), matches.prefix(30).map(\.id))
        XCTAssertTrue(model.hasMore)
        await model.loadMoreIfNeeded(after: model.entries[24])
        XCTAssertEqual(model.entries.count, 30)
        await model.loadMoreIfNeeded(after: model.entries[25])
        XCTAssertEqual(model.entries.map(\.id), matches.map(\.id))
        XCTAssertFalse(model.hasMore)

        await model.reload()
        XCTAssertEqual(model.entries.count, 30)
        model.query = "outro"
        await model.loadMore()
        XCTAssertEqual(model.entries.count, 30)
        await model.reload()
        let otherMatches = try await store.fetch(query: "outro", limit: 90)
        XCTAssertEqual(model.entries.map(\.id), otherMatches.map(\.id))
        XCTAssertEqual(model.entries.count, 30)
        XCTAssertFalse(model.hasMore)
        XCTAssertTrue(Set(model.entries.map(\.id)).isDisjoint(with: matches.map(\.id)))

        model.query = "Sem correspondência"
        await model.reload()
        await model.loadMore()
        XCTAssertTrue(model.entries.isEmpty)
        XCTAssertFalse(model.hasMore)
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.isLoadingMore)
        XCTAssertNil(model.paginationError)
        XCTAssertNil(model.errorMessage)
    }
}
