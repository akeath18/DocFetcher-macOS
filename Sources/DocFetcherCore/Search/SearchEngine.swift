import Foundation

public struct SearchOptions: Sendable {
    public var sort: SortOrder
    public var ascending: Bool?
    public var limit: Int
    public var fuzzy: Bool
    public var recordHistory: Bool
    public init(sort: SortOrder = .relevance, ascending: Bool? = nil, limit: Int = 200, fuzzy: Bool = false,
                recordHistory: Bool = false) {
        self.sort = sort; self.ascending = ascending; self.limit = limit; self.fuzzy = fuzzy
        self.recordHistory = recordHistory
    }
}

public enum SearchEngineError: Error { case invalidQuery(String) }

/// Queries the FTS5 index.
public final class SearchEngine: @unchecked Sendable {
    private let index: IndexDatabase
    public let store: SearchStore

    public init(index: IndexDatabase) {
        self.index = index
        self.store = SearchStore(index: index)
    }

    public func search(_ text: String, filters extra: SearchFilters = SearchFilters(),
                       options: SearchOptions = SearchOptions()) throws -> [SearchResult] {
        let query = SearchQuery(text)
        var filters = query.filters
        filters.extensions.formUnion(extra.extensions)
        filters.modifiedAfter = extra.modifiedAfter ?? filters.modifiedAfter
        filters.modifiedBefore = extra.modifiedBefore ?? filters.modifiedBefore

        var conditions: [String] = []
        var params: [SQLValue] = []
        let expand: ((String) -> [String])? = options.fuzzy ? { [self] in fuzzyVariants(of: $0) } : nil
        let fts = query.ftsExpression(expand: expand)
        if let fts { conditions.append("docs_fts MATCH ?"); params.append(.text(fts)) }
        if !filters.extensions.isEmpty {
            conditions.append("d.ext IN (\(Array(repeating: "?", count: filters.extensions.count).joined(separator: ",")))")
            params.append(contentsOf: filters.extensions.sorted().map { .text($0) })
        }
        if let a = filters.modifiedAfter { conditions.append("d.modified >= ?"); params.append(.double(a.timeIntervalSince1970)) }
        if let b = filters.modifiedBefore { conditions.append("d.modified <= ?"); params.append(.double(b.timeIntervalSince1970)) }

        let direction: (Bool) -> String = { defaultAsc in (options.ascending ?? defaultAsc) ? "ASC" : "DESC" }
        let order: String
        switch options.sort {
        case .relevance: order = fts == nil ? "d.filename COLLATE NOCASE ASC" : "score \(direction(true))"
        case .filename: order = "d.filename COLLATE NOCASE \(direction(true))"
        case .dateModified: order = "d.modified \(direction(false))"
        case .fileSize: order = "d.size \(direction(false))"
        }

        let sql: String
        if fts != nil {
            sql = """
                SELECT \(IndexDatabase.columns.split(separator: ",").map { "d." + $0.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: ", ")),
                       bm25(docs_fts, 8.0, 6.0, 2.0, 1.0) AS score
                FROM docs_fts JOIN documents d ON d.id = docs_fts.rowid
                WHERE \(conditions.joined(separator: " AND ")) ORDER BY \(order) LIMIT \(max(options.limit, 1))
                """
        } else {
            let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
            sql = """
                SELECT \(IndexDatabase.columns.split(separator: ",").map { "d." + $0.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: ", ")),
                       0.0 AS score
                FROM documents d \(whereClause) ORDER BY \(order) LIMIT \(max(options.limit, 1))
                """
        }

        let rows: [SQLRow]
        do { rows = try index.db.query(sql, params) }
        catch { throw SearchEngineError.invalidQuery("The search query could not be processed") }

        let terms = query.highlightTerms
        let results = rows.map { row -> SearchResult in
            let doc = IndexDatabase.makeDocument(row)
            let (snip, ranges) = Highlighter.snippet(in: doc.effectiveText, terms: terms)
            return SearchResult(document: doc, score: -(row.double("score") ?? 0), snippet: snip, snippetHighlights: ranges)
        }
        if options.recordHistory, !text.trimmingCharacters(in: .whitespaces).isEmpty {
            try? store.addHistory(query: text, resultCount: results.count)
        }
        return results
    }

    // MARK: Fuzzy matching & suggestions

    /// Indexed terms within a small edit distance of `term`.
    public func fuzzyVariants(of term: String) -> [String] {
        let t = term.lowercased()
        guard t.count >= 4 else { return [] }
        let maxDistance = t.count >= 8 ? 2 : 1
        let rows = (try? index.db.query(
            "SELECT term FROM docs_vocab WHERE length(term) BETWEEN ? AND ? LIMIT 50000",
            [.int(Int64(t.count - maxDistance)), .int(Int64(t.count + maxDistance))])) ?? []
        var scored: [(String, Int)] = []
        for row in rows {
            guard let candidate = row.string("term"), candidate != t else { continue }
            let d = Self.editDistance(t, candidate, limit: maxDistance)
            if d <= maxDistance { scored.append((candidate, d)) }
        }
        return scored.sorted { $0.1 < $1.1 || ($0.1 == $1.1 && $0.0 < $1.0) }.prefix(8).map { $0.0 }
    }

    /// Completion suggestions from indexed vocabulary and past searches.
    public func suggestions(for prefix: String, limit: Int = 8) -> [String] {
        let p = (prefix.split(whereSeparator: { $0.isWhitespace }).last.map(String.init) ?? "").lowercased()
        guard p.count >= 2 else { return [] }
        let escaped = p.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        var out: [String] = []
        let history = (try? store.history(limit: 200)) ?? []
        for h in history where h.query.lowercased().hasPrefix(prefix.lowercased()) && h.query.lowercased() != prefix.lowercased() {
            if !out.contains(h.query) { out.append(h.query) }
            if out.count >= limit / 2 { break }
        }
        let rows = (try? index.db.query(
            "SELECT term FROM docs_vocab WHERE term LIKE ? ESCAPE '\\' AND term != ? ORDER BY doc DESC, term LIMIT ?",
            [.text(escaped + "%"), .text(p), .int(Int64(limit))])) ?? []
        let base = prefix.dropLast(p.count)
        for r in rows {
            if let t = r.string("term") { out.append(String(base) + t) }
            if out.count >= limit { break }
        }
        return out
    }

    /// Levenshtein distance, returning `limit + 1` early when the distance exceeds `limit`.
    static func editDistance(_ a: String, _ b: String, limit: Int) -> Int {
        let s = Array(a), t = Array(b)
        if abs(s.count - t.count) > limit { return limit + 1 }
        var prev = Array(0...t.count)
        for i in 1...max(s.count, 1) where !s.isEmpty {
            var cur = [i] + Array(repeating: 0, count: t.count)
            var rowMin = cur[0]
            for j in 1...max(t.count, 1) where !t.isEmpty {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (s[i - 1] == t[j - 1] ? 0 : 1))
                rowMin = min(rowMin, cur[j])
            }
            if rowMin > limit { return limit + 1 }
            prev = cur
        }
        return prev[t.count]
    }
}
