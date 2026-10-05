import Foundation

public struct SearchResult: Identifiable, Sendable {
    public var id: Int64 { document.id ?? -1 }
    public let document: IndexableDocument
    /// Higher is better.
    public let score: Double
    /// Plain-text snippet around the match.
    public let snippet: String
    /// Ranges (UTF-16 offsets, NSRange-compatible) of matches within `snippet`.
    public let snippetHighlights: [NSRange]

    public init(document: IndexableDocument, score: Double, snippet: String, snippetHighlights: [NSRange]) {
        self.document = document
        self.score = score
        self.snippet = snippet
        self.snippetHighlights = snippetHighlights
    }
}
