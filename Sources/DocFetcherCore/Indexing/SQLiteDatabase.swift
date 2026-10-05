import Foundation
#if canImport(SQLite3)
import SQLite3
#else
import CSQLite
#endif

public enum SQLValue: Sendable, Equatable {
    case null
    case int(Int64)
    case double(Double)
    case text(String)
}

public struct SQLRow: Sendable {
    fileprivate var values: [String: SQLValue]

    public func string(_ column: String) -> String? {
        if case .text(let s)? = values[column] { return s }
        return nil
    }
    public func int(_ column: String) -> Int64? {
        switch values[column] {
        case .int(let i)?: return i
        case .double(let d)?: return Int64(d)
        default: return nil
        }
    }
    public func double(_ column: String) -> Double? {
        switch values[column] {
        case .double(let d)?: return d
        case .int(let i)?: return Double(i)
        default: return nil
        }
    }
}

public struct DatabaseError: Error, CustomStringConvertible {
    public let message: String
    public var description: String { message }
}

/// Thin, thread-safe wrapper around the system SQLite library.
public final class SQLiteDatabase: @unchecked Sendable {
    private var handle: OpaquePointer?
    private let lock = NSRecursiveLock()
    private var transactionDepth = 0

    public init(path: String) throws {
        if sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unable to open database"
            sqlite3_close(handle)
            throw DatabaseError(message: message)
        }
        sqlite3_busy_timeout(handle, 5000)
    }

    deinit { sqlite3_close(handle) }

    public func execute(_ sql: String, _ params: [SQLValue] = []) throws {
        _ = try run(sql, params, collect: false)
    }

    public func query(_ sql: String, _ params: [SQLValue] = []) throws -> [SQLRow] {
        try run(sql, params, collect: true)
    }

    public var lastInsertRowID: Int64 {
        lock.lock(); defer { lock.unlock() }
        return sqlite3_last_insert_rowid(handle)
    }

    public func scalarInt(_ sql: String, _ params: [SQLValue] = []) throws -> Int64? {
        try query(sql, params).first.flatMap { row in row.values.values.first.flatMap { v in
            if case .int(let i) = v { return i }
            if case .double(let d) = v { return Int64(d) }
            return nil
        } }
    }

    /// Runs `body` inside a transaction, rolling back when it throws.
    /// Nested calls join the outer transaction.
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        if transactionDepth > 0 { return try body() }
        transactionDepth += 1
        defer { transactionDepth -= 1 }
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func run(_ sql: String, _ params: [SQLValue], collect: Bool) throws -> [SQLRow] {
        lock.lock(); defer { lock.unlock() }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError(message: "\(String(cString: sqlite3_errmsg(handle))) [\(sql)]")
        }
        defer { sqlite3_finalize(stmt) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, value) in params.enumerated() {
            let idx = Int32(i + 1)
            switch value {
            case .null: sqlite3_bind_null(stmt, idx)
            case .int(let v): sqlite3_bind_int64(stmt, idx, v)
            case .double(let v): sqlite3_bind_double(stmt, idx, v)
            case .text(let v): sqlite3_bind_text(stmt, idx, v, -1, transient)
            }
        }

        var rows: [SQLRow] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW {
                guard collect else { break }
                var values: [String: SQLValue] = [:]
                for c in 0..<sqlite3_column_count(stmt) {
                    let name = String(cString: sqlite3_column_name(stmt, c))
                    switch sqlite3_column_type(stmt, c) {
                    case SQLITE_INTEGER: values[name] = .int(sqlite3_column_int64(stmt, c))
                    case SQLITE_FLOAT: values[name] = .double(sqlite3_column_double(stmt, c))
                    case SQLITE_NULL: values[name] = .null
                    default:
                        if let p = sqlite3_column_text(stmt, c) { values[name] = .text(String(cString: p)) } else { values[name] = .null }
                    }
                }
                rows.append(SQLRow(values: values))
            } else if rc == SQLITE_DONE {
                break
            } else {
                throw DatabaseError(message: String(cString: sqlite3_errmsg(handle)))
            }
        }
        return rows
    }
}

extension Optional where Wrapped == String {
    var sql: SQLValue { map { .text($0) } ?? .null }
}
extension Optional where Wrapped == Double {
    var sql: SQLValue { map { .double($0) } ?? .null }
}
