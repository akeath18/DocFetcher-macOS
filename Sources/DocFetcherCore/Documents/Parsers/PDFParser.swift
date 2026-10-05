import Foundation
#if canImport(PDFKit)
import PDFKit
#endif

public struct PDFParser: DocumentParser {
    public let name = "PDF"
    public let supportedExtensions: Set<String> = ["pdf"]
    /// A PDF averaging fewer non-whitespace characters per page than this is treated as a scan.
    public static let scannedCharsPerPageThreshold = 25

    public init() {}

    public func parse(url: URL) throws -> ParsedDocument {
        #if canImport(PDFKit)
        guard let doc = PDFDocument(url: url) else { throw ParserError.corrupted("cannot open PDF \(url.lastPathComponent)") }
        if doc.isLocked { throw ParserError.unreadable("PDF is password protected") }
        var pages: [String] = []
        for i in 0..<doc.pageCount { pages.append(doc.page(at: i)?.string ?? "") }
        let attrs = doc.documentAttributes ?? [:]
        let metadata = DocumentMetadata(
            title: (attrs[PDFDocumentAttribute.titleAttribute] as? String).flatMap { $0.isEmpty ? nil : $0 },
            author: (attrs[PDFDocumentAttribute.authorAttribute] as? String).flatMap { $0.isEmpty ? nil : $0 },
            created: attrs[PDFDocumentAttribute.creationDateAttribute] as? Date,
            modified: attrs[PDFDocumentAttribute.modificationDateAttribute] as? Date,
            pageCount: doc.pageCount)
        return ParsedDocument(text: pages.joined(separator: "\n\n"), metadata: metadata,
                              needsOCR: Self.looksScanned(pageTexts: pages))
        #else
        throw ParserError.unsupported("PDF parsing requires PDFKit (macOS)")
        #endif
    }

    public static func looksScanned(pageTexts: [String]) -> Bool {
        guard !pageTexts.isEmpty else { return false }
        let chars = pageTexts.reduce(0) { $0 + $1.filter { !$0.isWhitespace }.count }
        return chars / pageTexts.count < scannedCharsPerPageThreshold
    }
}
