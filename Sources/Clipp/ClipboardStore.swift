import Foundation
import CSQLite

enum ClipboardKind: String, Sendable {
    case text, image
}

struct ClipboardContent: Sendable {
    let kind: ClipboardKind
    let text: String?
    let imageData: Data?
    let thumbnail: Data?

    init(kind: ClipboardKind, text: String? = nil, imageData: Data? = nil, thumbnail: Data? = nil) {
        self.kind = kind
        self.text = text
        self.imageData = imageData
        self.thumbnail = thumbnail
    }
}

struct ClipboardEntry: Identifiable, Sendable {
    let id: Int64
    let kind: ClipboardKind
    let text: String?
    let thumbnail: Data?
    let createdAt: Date
    let sourceApp: String?
    let byteCount: Int
}

private enum ClipboardStoreError: LocalizedError {
    case sqlite(Int32, String)
    case invalidContent

    var errorDescription: String? {
        switch self {
        case let .sqlite(code, message):
            return "Não foi possível acessar o histórico (SQLite \(code)): \(message)"
        case .invalidContent:
            return "O conteúdo da área de transferência é inválido."
        }
    }
}

actor ClipboardStore {
    private let database: OpaquePointer
    private let directory: URL
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(directory: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let path = directory.appendingPathComponent("history.sqlite3").path
        var connection: OpaquePointer?
        let result = sqlite3_open_v2(path, &connection, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK, let connection else {
            let message = connection.map { String(cString: sqlite3_errmsg($0)) } ?? "Falha ao abrir o banco."
            if let connection { sqlite3_close(connection) }
            throw ClipboardStoreError.sqlite(result, message)
        }
        do {
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
            sqlite3_busy_timeout(connection, 5_000)
            var vacuumStatement: OpaquePointer?
            let prepared = sqlite3_prepare_v2(connection, "PRAGMA auto_vacuum", -1, &vacuumStatement, nil)
            guard prepared == SQLITE_OK, let vacuumStatement else {
                throw ClipboardStoreError.sqlite(prepared, String(cString: sqlite3_errmsg(connection)))
            }
            let stepped = sqlite3_step(vacuumStatement)
            let vacuumMode = sqlite3_column_int(vacuumStatement, 0)
            sqlite3_finalize(vacuumStatement)
            guard stepped == SQLITE_ROW else {
                throw ClipboardStoreError.sqlite(stepped, String(cString: sqlite3_errmsg(connection)))
            }
            // One-time migration lets retention release pages without copying the entire database per capture.
            try Self.execute("PRAGMA auto_vacuum = INCREMENTAL;" + (vacuumMode == 0 ? " VACUUM;" : ""), on: connection)
            try Self.execute("""
                PRAGMA journal_mode = WAL;
                CREATE TABLE IF NOT EXISTS clipboard_entries (
                    id INTEGER PRIMARY KEY,
                    kind TEXT NOT NULL CHECK (kind IN ('text', 'image')),
                    text TEXT,
                    preview TEXT,
                    image_data BLOB,
                    thumbnail BLOB,
                    created_at REAL NOT NULL,
                    source_app TEXT,
                    byte_count INTEGER NOT NULL CHECK (byte_count > 0),
                    CHECK (
                        (kind = 'text' AND text IS NOT NULL AND image_data IS NULL AND thumbnail IS NULL)
                        OR (kind = 'image' AND text IS NULL AND image_data IS NOT NULL)
                    )
                );
                CREATE INDEX IF NOT EXISTS clipboard_entries_date
                    ON clipboard_entries (created_at DESC, id DESC);
                """, on: connection)
            for suffix in ["-wal", "-shm"] where fileManager.fileExists(atPath: path + suffix) {
                try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path + suffix)
            }
        } catch {
            sqlite3_close(connection)
            throw error
        }
        database = connection
        self.directory = directory
    }

    deinit {
        sqlite3_close(database)
    }

    func insert(_ content: ClipboardContent, sourceApp: String?, createdAt: Date = Date()) throws {
        let byteCount: Int
        switch content.kind {
        case .text:
            guard let text = content.text, !text.isEmpty,
                  content.imageData == nil, content.thumbnail == nil else {
                throw ClipboardStoreError.invalidContent
            }
            byteCount = text.utf8.count
        case .image:
            guard let data = content.imageData, !data.isEmpty, content.text == nil,
                  content.thumbnail?.isEmpty != true else {
                throw ClipboardStoreError.invalidContent
            }
            byteCount = data.count
        }
        guard createdAt.timeIntervalSince1970.isFinite else { throw ClipboardStoreError.invalidContent }
        try withStatement("""
            INSERT INTO clipboard_entries
                (kind, text, preview, image_data, thumbnail, created_at, source_app, byte_count)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """) { statement in
            try bind(content.kind.rawValue, at: 1, to: statement)
            try bind(content.text, at: 2, to: statement)
            try bind(content.text.map { String($0.prefix(1_000)) }, at: 3, to: statement)
            try bind(content.imageData, at: 4, to: statement)
            try bind(content.thumbnail, at: 5, to: statement)
            try check(sqlite3_bind_double(statement, 6, createdAt.timeIntervalSince1970))
            try bind(sourceApp, at: 7, to: statement)
            try check(sqlite3_bind_int64(statement, 8, Int64(byteCount)))
            try finish(statement)
        }
    }

    func fetch(query: String = "", limit: Int = 100, before: ClipboardEntry? = nil) throws -> [ClipboardEntry] {
        guard limit > 0 else { throw ClipboardStoreError.invalidContent }
        // ponytail: literal substring search scans text; add FTS when the history makes search slow.
        let searchClause = query.isEmpty ? "" : "AND instr(lower(text), lower(?2)) > 0"
        let cursorClause = before == nil ? "" : "AND (created_at, id) < (?3, ?4)"
        return try withStatement("""
            SELECT id, kind, preview, thumbnail, created_at, source_app, byte_count
            FROM clipboard_entries
            WHERE 1 \(searchClause) \(cursorClause)
            ORDER BY created_at DESC, id DESC LIMIT ?1
            """) { statement in
            try check(sqlite3_bind_int64(statement, 1, Int64(limit)))
            if !query.isEmpty { try bind(query, at: 2, to: statement) }
            if let before {
                try check(sqlite3_bind_double(statement, 3, before.createdAt.timeIntervalSince1970))
                try check(sqlite3_bind_int64(statement, 4, before.id))
            }
            var entries: [ClipboardEntry] = []
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE { return entries }
                guard result == SQLITE_ROW else { throw sqliteError(result) }
                guard let kind = string(statement, column: 1).flatMap(ClipboardKind.init(rawValue:)) else {
                    throw ClipboardStoreError.invalidContent
                }
                entries.append(ClipboardEntry(
                    id: sqlite3_column_int64(statement, 0), kind: kind,
                    text: string(statement, column: 2), thumbnail: data(statement, column: 3),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)),
                    sourceApp: string(statement, column: 5), byteCount: Int(sqlite3_column_int64(statement, 6))
                ))
            }
        }
    }

    func content(id: Int64) throws -> ClipboardContent? {
        try withStatement("SELECT kind, text, image_data, thumbnail FROM clipboard_entries WHERE id = ?") { statement in
            try check(sqlite3_bind_int64(statement, 1, id))
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return nil }
            guard result == SQLITE_ROW else { throw sqliteError(result) }
            guard let kind = string(statement, column: 0).flatMap(ClipboardKind.init(rawValue:)) else {
                throw ClipboardStoreError.invalidContent
            }
            return ClipboardContent(kind: kind, text: string(statement, column: 1),
                                    imageData: data(statement, column: 2), thumbnail: data(statement, column: 3))
        }
    }

    func delete(id: Int64) throws {
        try withStatement("DELETE FROM clipboard_entries WHERE id = ?") { statement in
            try check(sqlite3_bind_int64(statement, 1, id))
            try finish(statement)
        }
    }

    func count() throws -> Int {
        try withStatement("SELECT count(*) FROM clipboard_entries") { statement in
            let result = sqlite3_step(statement)
            guard result == SQLITE_ROW else { throw sqliteError(result) }
            return Int(sqlite3_column_int64(statement, 0))
        }
    }

    func prune(keeping limit: Int) throws -> Int {
        guard limit >= 1 else { throw ClipboardStoreError.invalidContent }
        let removed = try withStatement("""
            DELETE FROM clipboard_entries WHERE (created_at, id) <= (
                SELECT created_at, id FROM clipboard_entries ORDER BY created_at DESC, id DESC LIMIT 1 OFFSET ?
            )
            """) { statement in
            try check(sqlite3_bind_int64(statement, 1, Int64(limit)))
            try finish(statement)
            return Int(sqlite3_changes(database))
        }
        if removed > 0 { compact() }
        return removed
    }

    func diskUsage() throws -> Int64 {
        func allocatedBytes(_ url: URL) throws -> Int64 {
            let values = try url.resourceValues(forKeys: [.fileAllocatedSizeKey, .fileSizeKey])
            return Int64(values.fileAllocatedSize ?? values.fileSize ?? 0)
        }
        var history: Int64 = 0
        for suffix in ["", "-wal", "-shm"] {
            let url = directory.appendingPathComponent("history.sqlite3" + suffix)
            do { history += try allocatedBytes(url) }
            catch let error as CocoaError where error.code == .fileReadNoSuchFile { continue }
        }
        return history
    }

    func clear() throws {
        try Self.execute("DELETE FROM clipboard_entries", on: database)
        compact()
    }

    private func compact() {
        // The committed deletion must not look like a failure if another reader temporarily prevents compaction.
        try? Self.execute("PRAGMA incremental_vacuum; PRAGMA wal_checkpoint(TRUNCATE);", on: database)
    }

    private static func execute(_ sql: String, on database: OpaquePointer) throws {
        let result = sqlite3_exec(database, sql, nil, nil, nil)
        guard result == SQLITE_OK else {
            throw ClipboardStoreError.sqlite(result, String(cString: sqlite3_errmsg(database)))
        }
    }

    private func withStatement<T>(_ sql: String, _ body: (OpaquePointer) throws -> T) throws -> T {
        var statement: OpaquePointer?
        try check(sqlite3_prepare_v2(database, sql, -1, &statement, nil))
        guard let statement else { throw ClipboardStoreError.invalidContent }
        defer { sqlite3_finalize(statement) }
        return try body(statement)
    }

    private func bind(_ value: String?, at index: Int32, to statement: OpaquePointer) throws {
        guard let value else { try check(sqlite3_bind_null(statement, index)); return }
        let result = value.withCString {
            sqlite3_bind_text64(statement, index, $0, UInt64(value.utf8.count), transient, UInt8(SQLITE_UTF8))
        }
        try check(result)
    }

    private func bind(_ value: Data?, at index: Int32, to statement: OpaquePointer) throws {
        guard let value else { try check(sqlite3_bind_null(statement, index)); return }
        let result = value.withUnsafeBytes {
            sqlite3_bind_blob64(statement, index, $0.baseAddress, UInt64($0.count), transient)
        }
        try check(result)
    }

    private func string(_ statement: OpaquePointer, column: Int32) -> String? {
        guard let bytes = sqlite3_column_text(statement, column) else { return nil }
        return String(decoding: UnsafeBufferPointer(start: bytes, count: Int(sqlite3_column_bytes(statement, column))), as: UTF8.self)
    }

    private func data(_ statement: OpaquePointer, column: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(statement, column) else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
    }

    private func finish(_ statement: OpaquePointer) throws {
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else { throw sqliteError(result) }
    }

    private func check(_ result: Int32) throws {
        guard result == SQLITE_OK else { throw sqliteError(result) }
    }

    private func sqliteError(_ code: Int32) -> ClipboardStoreError {
        .sqlite(code, String(cString: sqlite3_errmsg(database)))
    }
}
