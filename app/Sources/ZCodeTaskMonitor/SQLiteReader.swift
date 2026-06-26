import Foundation
import SQLite3

/// A tiny read-only SQLite3 wrapper. Opens the DB in read-only / URI mode so
/// SQLite automatically honors WAL (it reads committed + active WAL frames).
/// We never write, checkpoint, or hold the handle open between polls — the
/// connection lifetime is one query.
final class SQLiteReader {
    private let path: String

    init(_ path: String) {
        self.path = path
    }

    /// Run a query and map each row via `row`. `columns(sqlite, colCount)` reads
    /// column values; returns the accumulated result. Returns [] if the DB file
    /// is missing or locked.
    func query<T>(_ sql: String, map row: (OpaquePointer?, Int32) -> T?) -> [T] {
        // file: URI with mode=ro ensures read-only; immutable=0 lets WAL be seen.
        let uri = "file:\(path)?mode=ro&immutable=0"
        var db: OpaquePointer?
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_URI | SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return []
        }
        // 2s busy timeout so a transient ZCode write lock doesn't fail our read.
        sqlite3_busy_timeout(db, 2000)

        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            sqlite3_finalize(stmt)
            return []
        }
        defer { sqlite3_finalize(stmt) }

        let colCount = sqlite3_column_count(stmt)
        var out: [T] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let mapped = row(stmt, colCount) { out.append(mapped) }
        }
        return out
    }

    // MARK: - Column helpers (1-based index in our SQL selects for clarity)

    static func text(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let cstr = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: cstr)
    }

    static func int64(_ stmt: OpaquePointer?, _ index: Int32) -> Int64 {
        sqlite3_column_int64(stmt, index)
    }

    /// Returns nil when the column is NULL (e.g. completed_at before completion).
    static func int64OrNil(_ stmt: OpaquePointer?, _ index: Int32) -> Int64? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_int64(stmt, index)
    }
}
