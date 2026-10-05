import Foundation

public struct MergeRecord: Sendable, Equatable {
    public let id: Int64
    public let mergedDocumentID: Int64?
    public let title: String
    public let sourcePaths: [String]
    public let createdAt: Date
    public let undone: Bool
}

public enum MergeError: Error, Equatable {
    case notEnoughDocuments
    case documentNotFound(Int64)
    case notAMergedDocument
}

/// Combines several indexed documents into one searchable "virtual document" that links back to its sources.
public final class MergeManager: @unchecked Sendable {
    private let database: IndexDatabase
    init(database: IndexDatabase) { self.database = database }

    @discardableResult
    public func merge(documentIDs: [Int64], title: String) throws -> IndexableDocument {
        guard documentIDs.count >= 2 else { throw MergeError.notEnoughDocuments }
        let sources = try documentIDs.map { id -> IndexableDocument in
            guard let d = try database.document(id: id) else { throw MergeError.documentNotFound(id) }
            return d
        }
        let text = sources.map { "== \($0.filename) ==\n\($0.effectiveText)" }.joined(separator: "\n\n")
        var meta = DocumentMetadata(title: title)
        let authors = sources.compactMap { $0.metadata.author }
        meta.author = Array(NSOrderedSet(array: authors)).compactMap { $0 as? String }.joined(separator: ", ")
        if meta.author?.isEmpty == true { meta.author = nil }
        meta.created = sources.compactMap { $0.metadata.created }.min()
        meta.modified = sources.map(\.modified).max()
        meta.extra = ["sources": sources.map(\.path).joined(separator: "\n")]

        let uuid = UUID().uuidString
        var doc = IndexableDocument(
            path: "merged://\(uuid)", filename: title, fileExtension: "merged", mimeType: "application/x-docfetcher-merged",
            size: Int64(text.utf8.count), modified: Date(), metadata: meta, content: text, kind: .merged)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        return try database.db.transaction {
            let id = try database.upsert(doc)
            doc.id = id
            for (i, s) in sources.enumerated() {
                let json = (try? encoder.encode(s.metadata)).flatMap { String(data: $0, encoding: .utf8) }
                try database.db.execute("""
                    INSERT INTO merge_sources (merged_id, source_path, source_title, source_metadata_json, position)
                    VALUES (?,?,?,?,?)
                    """, [.int(id), .text(s.path), SQLValue.text(s.metadata.title ?? s.filename), json.sql, .int(Int64(i))])
            }
            try database.db.execute("""
                INSERT INTO merge_history (merged_id, title, source_paths, created_at) VALUES (?,?,?,?)
                """, [.int(id), .text(title), .text(sources.map(\.path).joined(separator: "\n")),
                      .double(Date().timeIntervalSince1970)])
            return doc
        }
    }

    /// Source file paths of a merged document, in merge order.
    public func sources(of mergedID: Int64) throws -> [String] {
        try database.db.query("SELECT source_path FROM merge_sources WHERE merged_id = ? ORDER BY position",
                              [.int(mergedID)]).compactMap { $0.string("source_path") }
    }

    /// Removes a merged document; the source documents are untouched.
    public func undoMerge(mergedID: Int64) throws {
        guard let doc = try database.document(id: mergedID), doc.kind == .merged else { throw MergeError.notAMergedDocument }
        try database.db.transaction {
            try database.deleteDocument(id: mergedID)
            try database.db.execute("DELETE FROM merge_sources WHERE merged_id = ?", [.int(mergedID)])
            try database.db.execute("UPDATE merge_history SET undone_at = ? WHERE merged_id = ? AND undone_at IS NULL",
                                    [.double(Date().timeIntervalSince1970), .int(mergedID)])
        }
    }

    public func history() throws -> [MergeRecord] {
        try database.db.query("SELECT id, merged_id, title, source_paths, created_at, undone_at FROM merge_history ORDER BY id DESC").map {
            MergeRecord(id: $0.int("id") ?? 0, mergedDocumentID: $0.int("merged_id"), title: $0.string("title") ?? "",
                        sourcePaths: ($0.string("source_paths") ?? "").split(separator: "\n").map(String.init),
                        createdAt: Date(timeIntervalSince1970: $0.double("created_at") ?? 0),
                        undone: $0.int("undone_at") != nil)
        }
    }
}
