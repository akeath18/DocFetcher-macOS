import XCTest
@testable import DocFetcherCore

final class SearchEngineTests: TempDirTestCase {
    func makeEngine() throws -> (IndexDatabase, SearchEngine) {
        let db = try makeIndex()
        try db.upsert(doc("apple.txt", "The quick brown fox jumps over the lazy dog", size: 100, title: "Fox story"))
        try db.upsert(doc("banana.txt", "Bananas are yellow and apples are red", size: 300))
        try db.upsert(doc("cherry.md", "Cherry pie recipe with apples and cinnamon", size: 200,
                          modified: Date(timeIntervalSince1970: 1_000_000)))
        return (db, SearchEngine(index: db))
    }

    func testBasicAndBoolean() throws {
        let (_, e) = try makeEngine()
        XCTAssertEqual(try e.search("apples").count, 2)
        XCTAssertEqual(try e.search("apples AND cinnamon").map(\.document.filename), ["cherry.md"])
        XCTAssertEqual(try e.search("fox OR cinnamon").count, 2)
        XCTAssertEqual(try e.search("apples NOT cinnamon").map(\.document.filename), ["banana.txt"])
        XCTAssertEqual(try e.search("apples -cinnamon").map(\.document.filename), ["banana.txt"])
        XCTAssertEqual(try e.search("(fox OR cinnamon) AND pie").map(\.document.filename), ["cherry.md"])
    }

    func testPhraseAndPrefix() throws {
        let (_, e) = try makeEngine()
        XCTAssertEqual(try e.search("\"brown fox\"").count, 1)
        XCTAssertEqual(try e.search("\"fox brown\"").count, 0)
        XCTAssertEqual(try e.search("cinn*").count, 1)
    }

    func testFieldAndFilters() throws {
        let (_, e) = try makeEngine()
        XCTAssertEqual(try e.search("filename:banana").map(\.document.filename), ["banana.txt"])
        XCTAssertEqual(try e.search("title:fox").count, 1)
        XCTAssertEqual(try e.search("content:bananas").count, 1)
        XCTAssertEqual(try e.search("apples type:md").map(\.document.filename), ["cherry.md"])
        XCTAssertEqual(try e.search("apples before:1970-02-01").map(\.document.filename), ["cherry.md"])
        XCTAssertEqual(try e.search("apples after:2000-01-01").map(\.document.filename), ["banana.txt"])
    }

    func testSpecialCharactersAndMalformedQueriesDoNotThrow() throws {
        let (_, e) = try makeEngine()
        for q in ["\"unterminated", "AND", "NOT apples", "((apples", "apples OR", "c++ ***", "foo:bar", "\"\"", "-", ")"] {
            XCTAssertNoThrow(try e.search(q), q)
        }
        XCTAssertEqual(try e.search("NOT apples").count, 3, "negation without operand is ignored → browse all")
    }

    func testSorting() throws {
        let (_, e) = try makeEngine()
        XCTAssertEqual(try e.search("", options: .init(sort: .filename)).map(\.document.filename), ["apple.txt", "banana.txt", "cherry.md"])
        XCTAssertEqual(try e.search("", options: .init(sort: .fileSize)).map(\.document.filename), ["banana.txt", "cherry.md", "apple.txt"])
        XCTAssertEqual(try e.search("", options: .init(sort: .dateModified)).last?.document.filename, "cherry.md")
        XCTAssertEqual(try e.search("", options: .init(sort: .fileSize, ascending: true)).first?.document.filename, "apple.txt")
    }

    func testRelevanceRanksFilenameAndFrequency() throws {
        let db = try makeIndex()
        try db.upsert(doc("notes.txt", "mentions report once"))
        try db.upsert(doc("report.txt", "something else entirely"))
        let r = try SearchEngine(index: db).search("report")
        XCTAssertEqual(r.first?.document.filename, "report.txt")
    }

    func testSnippetHighlights() throws {
        let (_, e) = try makeEngine()
        let r = try XCTUnwrap(e.search("lazy").first)
        let ns = r.snippet as NSString
        XCTAssertEqual(r.snippetHighlights.count, 1)
        XCTAssertEqual(ns.substring(with: r.snippetHighlights[0]), "lazy")
    }

    func testFuzzyMatching() throws {
        let (_, e) = try makeEngine()
        XCTAssertEqual(try e.search("cinamon").count, 0)
        XCTAssertEqual(try e.search("cinamon", options: .init(fuzzy: true)).map(\.document.filename), ["cherry.md"])
    }

    func testSuggestionsHistoryAndSavedSearches() throws {
        let (_, e) = try makeEngine()
        XCTAssertTrue(e.suggestions(for: "cinn").contains("cinnamon"))
        _ = try e.search("apples", options: .init(recordHistory: true))
        XCTAssertEqual(try e.store.history().first?.query, "apples")
        XCTAssertEqual(try e.store.history().first?.resultCount, 2)
        XCTAssertTrue(e.suggestions(for: "app").contains("apples"))
        try e.store.save(name: "Fruit", query: "apples OR bananas")
        try e.store.save(name: "Fruit", query: "apples")
        let saved = try e.store.savedSearches()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved[0].query, "apples")
        try e.store.deleteSavedSearch(id: saved[0].id)
        XCTAssertTrue(try e.store.savedSearches().isEmpty)
        try e.store.clearHistory()
        XCTAssertTrue(try e.store.history().isEmpty)
    }

    func testQueryParsing() {
        XCTAssertEqual(SearchQuery("a b").ftsExpression(), "\"a\" AND \"b\"")
        XCTAssertEqual(SearchQuery("a OR b").ftsExpression(), "\"a\" OR \"b\"")
        XCTAssertEqual(SearchQuery("title:\"x y\"").ftsExpression(), "title : \"x y\"")
        XCTAssertNil(SearchQuery("type:pdf").ftsExpression())
        XCTAssertEqual(SearchQuery("type:PDF a").filters.extensions, ["pdf"])
        XCTAssertEqual(SearchQuery("a -b").highlightTerms, ["a"])
    }

    func testEditDistance() {
        XCTAssertEqual(SearchEngine.editDistance("kitten", "sitten", limit: 2), 1)
        XCTAssertEqual(SearchEngine.editDistance("abc", "abcdefg", limit: 2), 3)
    }

    func testPerformanceOn250Documents() throws {
        let db = try makeIndex()
        let words = (0..<500).map { "word\($0)" }
        for i in 0..<250 {
            let text = (0..<300).map { words[($0 * 7 + i * 13) % 500] }.joined(separator: " ")
            try db.upsert(doc("d\(i).txt", text))
        }
        let e = SearchEngine(index: db)
        let start = Date()
        let r = try e.search("word7 AND word14")
        XCTAssertFalse(r.isEmpty)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0)
    }
}
