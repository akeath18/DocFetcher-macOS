import Foundation

public enum IndexDatabaseError: Error, CustomStringConvertible {
    case unsupportedVersion(Int)
    public var description: String {
        switch self {
        case .unsupportedVersion(let v): return "Index schema version \(v) is newer than this app supports"
        }
    }
}

/// SQLite + FTS5 persistence for indexed documents.
public final class IndexDatabase: @unchecked Sendable {
    public let db: SQLiteDatabase

    static let columns = """
        id, path, filename, ext, mime, size, modified, indexed_at, title, author, metadata_json, \
        content, ocr_text, ocr_confidence, use_ocr, kind
        """

    public init(path: String) throws {
        db = try SQLiteDatabase(path: path)
        try migrate()
    }

    public static func inMemory() throws -> IndexDatabase { try IndexDatabase(path: ":memory:") }

    // MARK: Migrations

    private func migrate() throws {
        let current = Int(try db.scalarInt("PRAGMA user_version") ?? 0)
        if current > SearchIndexVersion.schema { throw IndexDatabaseError.unsupportedVersion(current) }
        if current < 1 { try migrateToV1() }
        if current < 2 { try migrateToV2() }
        try db.execute("PRAGMA user_version = \(SearchIndexVersion.schema)")
        try invalidateIfParserChanged()
    }

    private func migrateToV1() throws {
        try db.transaction {
            try db.execute("""
                CREATE TABLE IF NOT EXISTS documents (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    path TEXT NOT NULL UNIQUE,
                    filename TEXT NOT NULL,
                    ext TEXT NOT NULL,
                    mime TEXT NOT NULL,
                    size INTEGER NOT NULL,
                    modified REAL NOT NULL,
                    indexed_at REAL NOT NULL,
                    title TEXT, author TEXT, metadata_json TEXT,
                    content TEXT NOT NULL,
                    ocr_text TEXT, ocr_confidence REAL,
                    use_ocr INTEGER NOT NULL DEFAULT 0,
                    kind TEXT NOT NULL DEFAULT 'file'
                )
                """)
            try db.execute("""
                CREATE VIRTUAL TABLE IF NOT EXISTS docs_fts USING fts5(
                    filename, title, author, content, tokenize = 'unicode61 remove_diacritics 2')
                """)
            try db.execute("CREATE VIRTUAL TABLE IF NOT EXISTS docs_vocab USING fts5vocab(docs_fts, 'row')")
            try db.execute("CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT)")
            try db.execute("CREATE TABLE IF NOT EXISTS indexed_folders (path TEXT PRIMARY KEY, added_at REAL NOT NULL)")
            try db.execute("""
                CREATE TABLE IF NOT EXISTS index_errors (
                    path TEXT PRIMARY KEY, message TEXT NOT NULL, occurred_at REAL NOT NULL)
                """)
        }
    }

    private func migrateToV2() throws {
        try db.transaction {
            try db.execute("""
                CREATE TABLE IF NOT EXISTS search_history (
                    id INTEGER PRIMARY KEY AUTOINCREMENT, query TEXT NOT NULL,
                    executed_at REAL NOT NULL, result_count INTEGER NOT NULL)
                """)
            try db.execute("""
                CREATE TABLE IF NOT EXISTS saved_searches (
                    id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE,
                    query TEXT NOT NULL, created_at REAL NOT NULL)
                """)
            try db.execute("""
                CREATE TABLE IF NOT EXISTS merge_sources (
                    merged_id INTEGER NOT NULL, source_path TEXT NOT NULL, source_title TEXT,
                    source_metadata_json TEXT, position INTEGER NOT NULL)
                """)
            try db.execute("""
                CREATE TABLE IF NOT EXISTS merge_history (
                    id INTEGER PRIMARY KEY AUTOINCREMENT, merged_id INTEGER, title TEXT NOT NULL,
                    source_paths TEXT NOT NULL, created_at REAL NOT NULL, undone_at REAL)
                """)
        }
    }

    private func invalidateIfParserChanged() throws {
        let stored = try db.query("SELECT value FROM meta WHERE key = 'parser_version'").first?.string("value")
        if stored != SearchIndexVersion.parser {
            // Force a re-index of all file documents on the next indexing run.
            try db.execute("UPDATE documents SET modified = 0 WHERE kind = 'file'")
            try db.execute("INSERT OR REPLACE INTO meta (key, value) VALUES ('parser_version', ?)",
                           [.text(SearchIndexVersion.parser)])
        }
    }

    // MARK: Documents

    /// Inserts or updates a document (keyed by path) and keeps the FTS table in sync.
    @discardableResult
    public func upsert(_ doc: IndexableDocument) throws -> Int64 {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = (try? encoder.encode(doc.metadata)).flatMap { String(data: $0, encoding: .utf8) }
        return try db.transaction {
            let existing = try db.scalarInt("SELECT id FROM documents WHERE path = ?", [.text(doc.path)])
            if let existing { try deleteFTS(id: existing) }
            try db.execute("""
                INSERT INTO documents (path, filename, ext, mime, size, modified, indexed_at, title, author,
                    metadata_json, content, ocr_text, ocr_confidence, use_ocr, kind)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(path) DO UPDATE SET filename=excluded.filename, ext=excluded.ext, mime=excluded.mime,
                    size=excluded.size, modified=excluded.modified, indexed_at=excluded.indexed_at,
                    title=excluded.title, author=excluded.author, metadata_json=excluded.metadata_json,
                    content=excluded.content, ocr_text=excluded.ocr_text, ocr_confidence=excluded.ocr_confidence,
                    use_ocr=excluded.use_ocr, kind=excluded.kind
                """, [.text(doc.path), .text(doc.filename), .text(doc.fileExtension), .text(doc.mimeType),
                      .int(doc.size), .double(doc.modified.timeIntervalSince1970),
                      .double(doc.indexedAt.timeIntervalSince1970), doc.metadata.title.sql, doc.metadata.author.sql,
                      json.sql, .text(doc.content), doc.ocrText.sql, doc.ocrConfidence.sql,
                      .int(doc.useOCR ? 1 : 0), .text(doc.kind.rawValue)])
            guard let id = try db.scalarInt("SELECT id FROM documents WHERE path = ?", [.text(doc.path)]) else {
                throw DatabaseError(message: "upsert failed for \(doc.path)")
            }
            try insertFTS(id: id, doc: doc)
            return id
        }
    }

    private func insertFTS(id: Int64, doc: IndexableDocument) throws {
        try db.execute("INSERT INTO docs_fts (rowid, filename, title, author, content) VALUES (?,?,?,?,?)",
                       [.int(id), .text(doc.filename), .text(doc.metadata.title ?? ""),
                        .text(doc.metadata.author ?? ""), .text(doc.effectiveText)])
    }

    private func deleteFTS(id: Int64) throws {
        try db.execute("DELETE FROM docs_fts WHERE rowid = ?", [.int(id)])
    }

    public func document(id: Int64) throws -> IndexableDocument? {
        try db.query("SELECT \(Self.columns) FROM documents WHERE id = ?", [.int(id)]).first.map(Self.makeDocument)
    }

    public func document(path: String) throws -> IndexableDocument? {
        try db.query("SELECT \(Self.columns) FROM documents WHERE path = ?", [.text(path)]).first.map(Self.makeDocument)
    }

    public func allDocuments() throws -> [IndexableDocument] {
        try db.query("SELECT \(Self.columns) FROM documents ORDER BY filename").map(Self.makeDocument)
    }

    /// Paths of file documents whose path starts with `prefix` (without loading document content).
    public func filePaths(under prefix: String) throws -> [String] {
        try db.query("SELECT path FROM documents WHERE kind = 'file' AND substr(path, 1, ?) = ?",
                     [.int(Int64(prefix.count)), .text(prefix)]).compactMap { $0.string("path") }
    }

    public func documentCount() throws -> Int {
        Int(try db.scalarInt("SELECT COUNT(*) FROM documents") ?? 0)
    }

    public func deleteDocument(id: Int64) throws {
        try db.transaction {
            try deleteFTS(id: id)
            try db.execute("DELETE FROM documents WHERE id = ?", [.int(id)])
        }
    }

    public func deleteDocument(path: String) throws {
        if let doc = try document(path: path), let id = doc.id { try deleteDocument(id: id) }
    }

    /// Switches a document between its original and OCR text and re-indexes it.
    public func setUseOCR(id: Int64, _ useOCR: Bool) throws {
        guard var doc = try document(id: id), doc.ocrText != nil else { return }
        doc.useOCR = useOCR
        try db.transaction {
            try db.execute("UPDATE documents SET use_ocr = ? WHERE id = ?", [.int(useOCR ? 1 : 0), .int(id)])
            try deleteFTS(id: id)
            try insertFTS(id: id, doc: doc)
        }
    }

    // MARK: Folders & errors

    public func addFolder(_ path: String) throws {
        try db.execute("INSERT OR IGNORE INTO indexed_folders (path, added_at) VALUES (?, ?)",
                       [.text(path), .double(Date().timeIntervalSince1970)])
    }

    public func removeFolder(_ path: String) throws {
        try db.execute("DELETE FROM indexed_folders WHERE path = ?", [.text(path)])
    }

    public func folders() throws -> [String] {
        try db.query("SELECT path FROM indexed_folders ORDER BY path").compactMap { $0.string("path") }
    }

    public func recordError(path: String, message: String) throws {
        try db.execute("INSERT OR REPLACE INTO index_errors (path, message, occurred_at) VALUES (?,?,?)",
                       [.text(path), .text(message), .double(Date().timeIntervalSince1970)])
    }

    public func clearError(path: String) throws {
        try db.execute("DELETE FROM index_errors WHERE path = ?", [.text(path)])
    }

    public func errors() throws -> [(path: String, message: String)] {
        try db.query("SELECT path, message FROM index_errors ORDER BY path").compactMap {
            guard let p = $0.string("path"), let m = $0.string("message") else { return nil }
            return (p, m)
        }
    }

    // MARK: Mapping

    static func makeDocument(_ row: SQLRow) -> IndexableDocument {
        var metadata = DocumentMetadata()
        if let json = row.string("metadata_json")?.data(using: .utf8) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            metadata = (try? decoder.decode(DocumentMetadata.self, from: json)) ?? metadata
        }
        return IndexableDocument(
            id: row.int("id"), path: row.string("path") ?? "", filename: row.string("filename") ?? "",
            fileExtension: row.string("ext") ?? "", mimeType: row.string("mime") ?? "",
            size: row.int("size") ?? 0, modified: Date(timeIntervalSince1970: row.double("modified") ?? 0),
            indexedAt: Date(timeIntervalSince1970: row.double("indexed_at") ?? 0), metadata: metadata,
            content: row.string("content") ?? "", ocrText: row.string("ocr_text"),
            ocrConfidence: row.double("ocr_confidence"), useOCR: (row.int("use_ocr") ?? 0) != 0,
            kind: DocumentKind(rawValue: row.string("kind") ?? "file") ?? .file)
    }
}
