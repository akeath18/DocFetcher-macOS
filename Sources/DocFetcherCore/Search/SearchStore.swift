import Foundation

public struct SearchHistoryEntry: Equatable, Sendable {
    public let query: String
    public let executedAt: Date
    public let resultCount: Int
}

public struct SavedSearch: Equatable, Sendable, Identifiable {
    public let id: Int64
    public let name: String
    public let query: String
    public let createdAt: Date
}

/// Persists search history and saved queries.
public final class SearchStore: @unchecked Sendable {
    private let index: IndexDatabase
    init(index: IndexDatabase) { self.index = index }

    public func addHistory(query: String, resultCount: Int) throws {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        try index.db.transaction {
            try index.db.execute("DELETE FROM search_history WHERE query = ?", [.text(q)])
            try index.db.execute("INSERT INTO search_history (query, executed_at, result_count) VALUES (?,?,?)",
                                 [.text(q), .double(Date().timeIntervalSince1970), .int(Int64(resultCount))])
            try index.db.execute("""
                DELETE FROM search_history WHERE id NOT IN (SELECT id FROM search_history ORDER BY id DESC LIMIT 500)
                """)
        }
    }

    public func history(limit: Int = 50) throws -> [SearchHistoryEntry] {
        try index.db.query("SELECT query, executed_at, result_count FROM search_history ORDER BY id DESC LIMIT ?",
                           [.int(Int64(limit))]).map {
            SearchHistoryEntry(query: $0.string("query") ?? "",
                               executedAt: Date(timeIntervalSince1970: $0.double("executed_at") ?? 0),
                               resultCount: Int($0.int("result_count") ?? 0))
        }
    }

    public func clearHistory() throws { try index.db.execute("DELETE FROM search_history") }

    @discardableResult
    public func save(name: String, query: String) throws -> Int64 {
        try index.db.execute("""
            INSERT INTO saved_searches (name, query, created_at) VALUES (?,?,?)
            ON CONFLICT(name) DO UPDATE SET query = excluded.query
            """, [.text(name), .text(query), .double(Date().timeIntervalSince1970)])
        return try index.db.scalarInt("SELECT id FROM saved_searches WHERE name = ?", [.text(name)]) ?? 0
    }

    public func savedSearches() throws -> [SavedSearch] {
        try index.db.query("SELECT id, name, query, created_at FROM saved_searches ORDER BY name COLLATE NOCASE").map {
            SavedSearch(id: $0.int("id") ?? 0, name: $0.string("name") ?? "", query: $0.string("query") ?? "",
                        createdAt: Date(timeIntervalSince1970: $0.double("created_at") ?? 0))
        }
    }

    public func deleteSavedSearch(id: Int64) throws {
        try index.db.execute("DELETE FROM saved_searches WHERE id = ?", [.int(id)])
    }
}
