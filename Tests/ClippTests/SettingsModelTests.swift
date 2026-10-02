import AppKit
import CSQLite
import XCTest
@testable import Clipp

final class SettingsModelTests: XCTestCase {
    @MainActor
    func testSettingsPersistAndRetentionAppliesToExistingAndFutureCopies() async throws {
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
        func capture(_ text: String) async {
            pasteboard.clearContents()
            XCTAssertTrue(pasteboard.setString(text, forType: .string))
            await model.poll()
        }

        XCTAssertTrue(model.notificationsEnabled)
        XCTAssertTrue(model.showCopiedTextInNotifications)
        XCTAssertTrue(model.soundEnabled)
        XCTAssertEqual(model.historyLimit, 0)
        model.showCopiedTextInNotifications = false
        model.notificationsEnabled = false
        XCTAssertFalse(model.showCopiedTextInNotifications)
        model.notificationsEnabled = true
        XCTAssertFalse(model.showCopiedTextInNotifications)
        model.notificationsEnabled = false
        model.soundEnabled = false
        await capture("Primeiro")
        await capture("Segundo")
        await model.applyHistoryLimit(1)
        XCTAssertEqual(model.entries.map(\.text), ["Segundo"])
        XCTAssertEqual(model.total, 1)
        XCTAssertEqual(model.historyLimit, 1)

        let reopened = ClipboardModel(pasteboard: pasteboard, directory: directory, defaults: defaults)
        XCTAssertFalse(reopened.notificationsEnabled)
        XCTAssertFalse(reopened.showCopiedTextInNotifications)
        XCTAssertFalse(reopened.soundEnabled)
        XCTAssertEqual(reopened.historyLimit, 1)
        reopened.showCopiedTextInNotifications = true
        reopened.soundEnabled = true
        let reopenedAgain = ClipboardModel(pasteboard: pasteboard, directory: directory, defaults: defaults)
        XCTAssertFalse(reopenedAgain.notificationsEnabled)
        XCTAssertTrue(reopenedAgain.showCopiedTextInNotifications)
        XCTAssertTrue(reopenedAgain.soundEnabled)

        await capture("Terceiro")
        XCTAssertEqual(model.entries.map(\.text), ["Terceiro"])
        XCTAssertEqual(model.total, 1)
        await model.applyHistoryLimit(-1)
        XCTAssertEqual(model.historyLimit, 1)
        XCTAssertEqual(defaults.integer(forKey: "historyLimit"), 1)
        XCTAssertEqual(model.entries.map(\.text), ["Terceiro"])
        XCTAssertEqual(model.total, 1)
        XCTAssertNotNil(model.settingsMessage)

        await model.applyHistoryLimit(0)
        await capture("Quarto")
        await capture("Quinto")
        XCTAssertEqual(model.historyLimit, 0)
        XCTAssertEqual(defaults.integer(forKey: "historyLimit"), 0)
        XCTAssertEqual(model.entries.map(\.text), ["Quinto", "Quarto", "Terceiro"])
        XCTAssertEqual(model.total, 3)
        let count = try await store.count()
        XCTAssertEqual(count, 3)
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testClearDeletesHistoryUpdatesUsageAndOnlyCapturesNewChanges() async throws {
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
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString(String(repeating: "Histórico 📝 ", count: 16_000), forType: .string))
        await model.poll()
        XCTAssertEqual(model.total, 1)
        let usageBefore = model.diskUsage.historyBytes
        XCTAssertGreaterThan(usageBefore, 0)

        await model.clearHistory()
        XCTAssertTrue(model.entries.isEmpty)
        XCTAssertEqual(model.total, 0)
        XCTAssertFalse(model.hasMore)
        XCTAssertFalse(model.isMaintaining)
        let clearedCount = try await store.count()
        XCTAssertEqual(clearedCount, 0)
        // An empty SQLite database still occupies disk space.
        XCTAssertGreaterThan(model.diskUsage.historyBytes, 0)
        XCTAssertLessThan(model.diskUsage.historyBytes, usageBefore)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Backups").path))
        XCTAssertEqual(model.settingsMessage, "Histórico limpo.")

        await model.poll()
        XCTAssertTrue(model.entries.isEmpty)
        XCTAssertEqual(model.total, 0)
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("Após a limpeza", forType: .string))
        await model.poll()
        XCTAssertEqual(model.entries.map(\.text), ["Após a limpeza"])
        XCTAssertEqual(model.total, 1)
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testClearPreservesPendingCopiesOnFailureAndDiscardsThemOnSuccess() async throws {
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
        func capture(_ text: String) async {
            pasteboard.clearContents()
            XCTAssertTrue(pasteboard.setString(text, forType: .string))
            await model.poll()
        }
        await capture("Persistida")
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(directory.appendingPathComponent("history.sqlite3").path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        func execute(_ sql: String) {
            XCTAssertEqual(sqlite3_exec(database, sql, nil, nil, nil), SQLITE_OK)
        }
        execute("CREATE TRIGGER block_insert BEFORE INSERT ON clipboard_entries BEGIN SELECT RAISE(ABORT, 'test'); END")
        execute("CREATE TRIGGER block_delete BEFORE DELETE ON clipboard_entries BEGIN SELECT RAISE(ABORT, 'test'); END")
        await capture("Pendente preservada")
        XCTAssertNotNil(model.errorMessage)
        await model.clearHistory()
        XCTAssertEqual(model.total, 1)
        XCTAssertEqual(model.entries.map(\.text), ["Persistida"])
        XCTAssertFalse(model.isMaintaining)
        XCTAssertTrue(model.settingsMessage?.hasPrefix("A limpeza não foi concluída:") == true)

        execute("DROP TRIGGER block_delete; DROP TRIGGER block_insert")
        await model.poll()
        XCTAssertEqual(model.entries.map(\.text), ["Pendente preservada", "Persistida"])

        execute("CREATE TRIGGER block_insert BEFORE INSERT ON clipboard_entries BEGIN SELECT RAISE(ABORT, 'test'); END")
        await capture("Pendente descartada")
        await model.clearHistory()
        XCTAssertEqual(model.total, 0)
        XCTAssertNil(model.errorMessage)
        execute("DROP TRIGGER block_insert")
        await model.poll()
        XCTAssertTrue(model.entries.isEmpty)
        XCTAssertEqual(model.total, 0)
        await capture("Nova cópia")
        XCTAssertEqual(model.entries.map(\.text), ["Nova cópia"])
    }
}
