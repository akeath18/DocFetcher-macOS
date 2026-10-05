import XCTest
@testable import DocFetcherCore

final class OCRTests: XCTestCase {
    func testCleanerRemovesNoise() {
        let raw = "The qu|ick brown ﬁx\n~ ^ ` | ~\n-----------------\nsecond ~ line with exam-\nple text\n\n\n\nend ¦"
        let (clean, removed) = OCRTextCleaner.clean(raw)
        XCTAssertFalse(clean.contains("|"))
        XCTAssertFalse(clean.contains("~"))
        XCTAssertTrue(clean.contains("quick brown fix"))
        XCTAssertTrue(clean.contains("example text"))
        XCTAssertFalse(clean.contains("---"))
        XCTAssertFalse(clean.contains("\n\n\n"))
        XCTAssertGreaterThan(removed, 0)
    }

    func testCleanerKeepsLegitimatePunctuation() {
        let text = "Total: $1,200.00 (approx.) - see p. 4 & 5, e-mail a@b.com"
        XCTAssertEqual(OCRTextCleaner.clean(text).text, text)
    }

    func testQualityScoreAndResult() {
        let good = OCRTextCleaner.qualityScore("This is a perfectly normal sentence about documents.")
        let bad = OCRTextCleaner.qualityScore("xzqk wpvtr #$%^ bcdfgh ,;:; qqqqqq")
        XCTAssertGreaterThan(good, 0.9)
        XCTAssertLessThan(bad, 0.4)
        XCTAssertEqual(OCRTextCleaner.qualityScore(""), 0)

        let r = OCRTextCleaner.makeResult(rawText: "Hello | world", engineConfidence: 0.9, pageConfidences: [0.9])
        XCTAssertEqual(r.cleanedText, "Hello world")
        XCTAssertEqual(r.text(cleaned: false), "Hello | world")
        XCTAssertEqual(r.text(cleaned: true), "Hello world")
        XCTAssertEqual(r.removedSymbolCount, 1)
        XCTAssertTrue((0...1).contains(r.confidence))
    }

    func testFallbackProcessor() async throws {
        struct Failing: OCRProcessor { func recognize(url: URL) async throws -> OCRResult { throw ParserError.unsupported("no") } }
        struct Fixed: OCRProcessor { func recognize(url: URL) async throws -> OCRResult { OCRTextCleaner.makeResult(rawText: "ok text", engineConfidence: 1) } }
        let r = try await FallbackOCRProcessor([Failing(), Fixed()]).recognize(url: URL(fileURLWithPath: "/x"))
        XCTAssertEqual(r.cleanedText, "ok text")
        do { _ = try await FallbackOCRProcessor([Failing()]).recognize(url: URL(fileURLWithPath: "/x")); XCTFail() } catch {}
    }

    func testIndexerStoresOCRTextForScans() async throws {
        struct Fixed: OCRProcessor { func recognize(url: URL) async throws -> OCRResult { OCRTextCleaner.makeResult(rawText: "scanned invoice text", engineConfidence: 0.8) } }
        struct ScanParser: DocumentParser {
            let name = "scan"; let supportedExtensions: Set<String> = ["scan"]
            func parse(url: URL) throws -> ParsedDocument { ParsedDocument(text: "", needsOCR: true) }
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("x".utf8).write(to: dir.appendingPathComponent("a.scan"))
        let db = try IndexDatabase.inMemory()
        let registry = ParserRegistry(parsers: [ScanParser()])
        let outcome = await DocumentIndexer(database: db, registry: registry, ocr: Fixed()).indexFile(dir.appendingPathComponent("a.scan"))
        XCTAssertEqual(outcome, .indexed)
        let doc = try XCTUnwrap(db.allDocuments().first)
        XCTAssertTrue(doc.useOCR)
        XCTAssertNotNil(doc.ocrConfidence)
        XCTAssertEqual(try SearchEngine(index: db).search("invoice").count, 1)
    }
}
