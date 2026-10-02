import Foundation
import XCTest
@testable import Clipp

final class ClipboardMaintenanceTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    func testClearDeletesTextAndImagesPermanentlyWithoutBackup() async throws {
        var store: ClipboardStore? = try ClipboardStore(directory: directory)
        try await store!.insert(ClipboardContent(kind: .text, text: "Texto integral 👋"), sourceApp: "Editor")
        let image = Data((0..<300_000).map { UInt8(truncatingIfNeeded: $0) })
        try await store!.insert(ClipboardContent(kind: .image, imageData: image, thumbnail: Data([0, 1, 255])),
                                sourceApp: "Imagens")
        let before = try await store!.diskUsage()
        XCTAssertGreaterThan(before.historyBytes, 0)

        try await store!.clear()
        let count = try await store!.count()
        XCTAssertEqual(count, 0)
        let after = try await store!.diskUsage()
        XCTAssertGreaterThan(after.historyBytes, 0)
        XCTAssertLessThan(after.historyBytes, before.historyBytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Backups").path))

        store = nil
        let reopened = try ClipboardStore(directory: directory)
        let reopenedCount = try await reopened.count()
        XCTAssertEqual(reopenedCount, 0)
        let entries = try await reopened.fetch()
        XCTAssertTrue(entries.isEmpty)
    }

    func testRetentionUsesDateThenIDAndAcceptsOneOrOneThousand() async throws {
        let store = try ClipboardStore(directory: directory)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        for index in 0..<1_002 {
            try await store.insert(ClipboardContent(kind: .text, text: String(index)), sourceApp: nil, createdAt: date)
        }
        let removed = try await store.prune(keeping: 1_000)
        XCTAssertEqual(removed, 2)
        let entries = try await store.fetch(limit: 1_100)
        XCTAssertEqual(entries.count, 1_000)
        XCTAssertEqual(entries.first?.text, "1001")
        XCTAssertEqual(entries.last?.text, "2")
        try await store.insert(ClipboardContent(kind: .text, text: "Mais novo por data"), sourceApp: nil,
                               createdAt: date.addingTimeInterval(1))
        try await store.insert(ClipboardContent(kind: .text, text: "ID maior, data anterior"), sourceApp: nil,
                               createdAt: date)
        let removedForOne = try await store.prune(keeping: 1)
        XCTAssertEqual(removedForOne, 1_001)
        let remaining = try await store.fetch()
        XCTAssertEqual(remaining.map(\.text), ["Mais novo por data"])
        let noRemoval = try await store.prune(keeping: Int.max)
        XCTAssertEqual(noRemoval, 0)
        do {
            _ = try await store.prune(keeping: 0)
            XCTFail("A zero retention limit must not delete all history")
        } catch { }
        let finalCount = try await store.count()
        XCTAssertEqual(finalCount, 1)
    }
}
