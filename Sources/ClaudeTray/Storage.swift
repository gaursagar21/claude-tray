import Foundation
import SQLite3

final class Storage: @unchecked Sendable {
    private var db: OpaquePointer?

    init(path: String) throws {
        if sqlite3_open(path, &db) != SQLITE_OK {
            throw StorageError.openFailed(String(cString: sqlite3_errmsg(db)))
        }
        try createSchema()
    }

    deinit { sqlite3_close(db) }

    // MARK: - Schema

    private func createSchema() throws {
        let sql = """
            CREATE TABLE IF NOT EXISTS requests (
                id           TEXT PRIMARY KEY,
                timestamp    REAL NOT NULL,
                model        TEXT,
                input_tokens INTEGER DEFAULT 0,
                output_tokens INTEGER DEFAULT 0,
                request_body  TEXT,
                response_body TEXT,
                is_streaming  INTEGER DEFAULT 0,
                duration_ms   INTEGER DEFAULT 0,
                status_code   INTEGER DEFAULT 0
            );
            CREATE INDEX IF NOT EXISTS idx_ts ON requests(timestamp DESC);
        """
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw StorageError.schemaFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    // MARK: - Write

    func save(log: RequestLog, requestBody: String, responseBody: String) {
        let sql = """
            INSERT OR REPLACE INTO requests
            (id, timestamp, model, input_tokens, output_tokens, request_body, response_body, is_streaming, duration_ms, status_code)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, log.id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_double(stmt, 2, log.timestamp.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 3, log.model, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_int(stmt, 4, Int32(log.inputTokens))
        sqlite3_bind_int(stmt, 5, Int32(log.outputTokens))
        sqlite3_bind_text(stmt, 6, requestBody, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 7, responseBody, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_int(stmt, 8, log.isStreaming ? 1 : 0)
        sqlite3_bind_int(stmt, 9, Int32(log.durationMs))
        sqlite3_bind_int(stmt, 10, Int32(log.statusCode))

        sqlite3_step(stmt)
    }

    // MARK: - Read (metadata only — body strings stay in DB until needed)

    func fetchRequests(limit: Int = 200) -> [RequestLog] {
        let sql = """
            SELECT id, timestamp, model, input_tokens, output_tokens,
                   is_streaming, duration_ms, status_code
            FROM requests
            ORDER BY timestamp DESC
            LIMIT ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(limit))

        var results: [RequestLog] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id        = String(cString: sqlite3_column_text(stmt, 0))
            let ts        = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
            let model     = String(cString: sqlite3_column_text(stmt, 2))
            let inputTok  = Int(sqlite3_column_int(stmt, 3))
            let outputTok = Int(sqlite3_column_int(stmt, 4))
            let streaming = sqlite3_column_int(stmt, 5) != 0
            let duration  = Int(sqlite3_column_int(stmt, 6))
            let status    = Int(sqlite3_column_int(stmt, 7))

            results.append(RequestLog(
                id: id, timestamp: ts, model: model,
                inputTokens: inputTok, outputTokens: outputTok,
                isStreaming: streaming, durationMs: duration, statusCode: status
            ))
        }
        return results
    }

    // MARK: - Lazy body fetch — called only when the inspector/detail opens

    func fetchBodies(id: String) -> RequestBodies? {
        let sql = "SELECT request_body, response_body FROM requests WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        let reqBody = String(cString: sqlite3_column_text(stmt, 0))
        let resBody = String(cString: sqlite3_column_text(stmt, 1))
        return RequestBodies(requestBody: reqBody, responseBody: resBody)
    }

    func deleteAll() {
        sqlite3_exec(db, "DELETE FROM requests", nil, nil, nil)
    }
}

enum StorageError: Error {
    case openFailed(String)
    case schemaFailed(String)
}
