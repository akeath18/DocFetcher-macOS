import XCTest
@testable import DocFetcherCore

final class IndexingTests: TempDirTestCase {
    func testIncrementalIndexing() async throws {
        let db = try makeIndex()
        let indexer = DocumentIndexer(database: db)
        let a = try write("a.txt", "alpha content")
        try write("b.html", "<html><title>B</title><body>beta content</body></html>")
        try write("ignored.bin", "xxx")

        var s = await indexer.indexFolder(dir)
        XCTAssertEqual(s.indexed, 2)
        XCTAssertEqual(try db.documentCount(), 2)

        s = await indexer.indexFolder(dir)
        XCTAssertEqual(s.indexed, 0)
        XCTAssertEqual(s.unchanged, 2)

        try "alpha changed gamma".write(to: a, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: a.path)
        s = await indexer.indexFolder(dir)
        XCTAssertEqual(s.indexed, 1)
        let engine = SearchEngine(index: db)
        XCTAssertEqual(try engine.search("gamma").count, 1)
        XCTAssertEqual(try engine.search("content").count, 1)

        try FileManager.default.removeItem(at: a)
        s = await indexer.indexFolder(dir)
        XCTAssertEqual(s.removed, 1)
        XCTAssertEqual(try engine.search("gamma").count, 0)
    }

    func testCorruptedFilesAreRecordedNotFatal() async throws {
        let db = try makeIndex()
        try write("good.txt", "fine document")
        try write("bad.docx", "this is not a zip")
        try write("bad.pdf", "not a pdf")
        try write("bad.rtf", "not rtf")
        let s = await DocumentIndexer(database: db).indexFolder(dir)
        XCTAssertEqual(s.indexed, 1)
        XCTAssertEqual(s.failed, 3)
        XCTAssertEqual(try db.errors().count, 3)
    }

    func testPersistenceAndVersioning() throws {
        let path = dir.appendingPathComponent("index.sqlite").path
        do {
            let db = try IndexDatabase(path: path)
            try db.upsert(doc("x.txt", "persisted text"))
            try db.addFolder("/some/folder")
        }
        let db = try IndexDatabase(path: path)
        XCTAssertEqual(try SearchEngine(index: db).search("persisted").count, 1)
        XCTAssertEqual(try db.folders(), ["/some/folder"])
        XCTAssertEqual(try db.db.scalarInt("PRAGMA user_version"), Int64(SearchIndexVersion.schema))
    }

    func testMigrationFromV1() throws {
        let path = dir.appendingPathComponent("old.sqlite").path
        do {
            let old = try IndexDatabase(path: path)
            try old.upsert(doc("old.txt", "legacy entry"))
            for t in ["search_history", "saved_searches", "merge_sources", "merge_history"] { try old.db.execute("DROP TABLE \(t)") }
            try old.db.execute("PRAGMA user_version = 1")
        }
        let db = try IndexDatabase(path: path)
        XCTAssertNoThrow(try SearchEngine(index: db).store.save(name: "n", query: "q"))
        XCTAssertEqual(try SearchEngine(index: db).search("legacy").count, 1)
    }

    func testNewerSchemaIsRejected() throws {
        let path = dir.appendingPathComponent("future.sqlite").path
        try SQLiteDatabase(path: path).execute("PRAGMA user_version = 999")
        XCTAssertThrowsError(try IndexDatabase(path: path))
    }

    func testBulkIndexingSpeed() async throws {
        let db = try makeIndex()
        for i in 0..<250 {
            try write("doc\(i).txt", (0..<200).map { "token\($0 * (i + 1) % 997)" }.joined(separator: " "))
        }
        let start = Date()
        let s = await DocumentIndexer(database: db).indexFolder(dir)
        XCTAssertEqual(s.indexed, 250)
        XCTAssertLessThan(Date().timeIntervalSince(start), 30)
    }

    func testIndexManagerBackgroundIndexing() async throws {
        try write("one.txt", "managed document")
        let manager = IndexManager(database: try makeIndex())
        try await manager.addFolder(dir)
        let summary = await manager.startIndexing().value
        XCTAssertEqual(summary.indexed, 1)
        let status = await manager.status
        XCTAssertFalse(status.isIndexing)
        XCTAssertEqual(try manager.searchEngine.search("managed").count, 1)
        try await manager.removeFolder(dir.standardizedFileURL.path)
        XCTAssertEqual(try manager.database.documentCount(), 0)
    }

    func testMergeAndUndo() throws {
        let db = try makeIndex()
        let a = try db.upsert(doc("a.txt", "alpha", title: "Alpha"))
        let b = try db.upsert(doc("b.txt", "beta"))
        let merger = MergeManager(database: db)
        XCTAssertThrowsError(try merger.merge(documentIDs: [a], title: "x"))
        let merged = try merger.merge(documentIDs: [a, b], title: "Combined")
        let id = try XCTUnwrap(merged.id)
        let engine = SearchEngine(index: db)
        XCTAssertEqual(try engine.search("beta").count, 2)
        XCTAssertEqual(try merger.sources(of: id), ["/tmp/a.txt", "/tmp/b.txt"])
        XCTAssertEqual(try db.document(id: id)?.kind, .merged)
        XCTAssertEqual(try merger.history().count, 1)
        try merger.undoMerge(mergedID: id)
        XCTAssertEqual(try engine.search("beta").count, 1)
        XCTAssertEqual(try merger.history().first?.undone, true)
        XCTAssertThrowsError(try merger.undoMerge(mergedID: a))
    }

    func testOCRToggleChangesSearchableText() throws {
        let db = try makeIndex()
        var d = doc("scan.pdf", "")
        d.ocrText = "recognized words"
        d.useOCR = true
        let id = try db.upsert(d)
        let engine = SearchEngine(index: db)
        XCTAssertEqual(try engine.search("recognized").count, 1)
        try db.setUseOCR(id: id, false)
        XCTAssertEqual(try engine.search("recognized").count, 0)
        try db.setUseOCR(id: id, true)
        XCTAssertEqual(try engine.search("recognized").count, 1)
    }

    func testExport() throws {
        let db = try makeIndex()
        try db.upsert(doc("=evil.txt", "hello \"quoted\" world"))
        let results = try SearchEngine(index: db).search("hello")
        let csv = String(decoding: try ResultExporter.export(results, format: .csv), as: UTF8.self)
        XCTAssertTrue(csv.contains("\"'=evil.txt\""))
        let json = try JSONSerialization.jsonObject(with: ResultExporter.export(results, format: .json)) as? [[String: Any]]
        XCTAssertEqual(json?.count, 1)
        let pdf = try ResultExporter.export(results, format: .pdf)
        XCTAssertTrue(pdf.starts(with: Array("%PDF-1.4".utf8)))
        XCTAssertNotNil(String(decoding: pdf, as: UTF8.self).range(of: "%%EOF"))
    }

    func testHighlighterRanges() {
        let r = Highlighter.ranges(of: ["café"], in: "Un CAFE, un café.")
        XCTAssertEqual(r.count, 2)
    }
}
