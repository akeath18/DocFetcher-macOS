import Foundation

public protocol DocumentParser: Sendable {
    var name: String { get }
    var supportedExtensions: Set<String> { get }
    /// Parses the file. Must throw (never crash) on corrupted or malformed input.
    func parse(url: URL) throws -> ParsedDocument
}

/// Selects a parser for a file based on its content type and extension.
public final class ParserRegistry: @unchecked Sendable {
    private var parsers: [DocumentParser] = []

    public init(parsers: [DocumentParser]? = nil) {
        if let parsers { self.parsers = parsers } else { registerDefaults() }
    }

    public static let shared = ParserRegistry()

    private func registerDefaults() {
        parsers = [
            TextParser(), HTMLParser(), RTFParser(), PDFParser(), OfficeParser(), EPUBParser(),
            SVGParser(), LegacyOfficeParser(), MediaMetadataParser(), ImageParser(),
        ]
        parsers.append(ArchiveParser(registry: self))
    }

    public func register(_ parser: DocumentParser) { parsers.insert(parser, at: 0) }

    public var supportedExtensions: Set<String> { parsers.reduce(into: []) { $0.formUnion($1.supportedExtensions) } }

    public func parser(for url: URL) -> DocumentParser? {
        let ext = url.pathExtension.lowercased()
        if let p = parsers.first(where: { $0.supportedExtensions.contains(ext) }) { return p }
        return nil
    }

    public func canParse(_ url: URL) -> Bool { parser(for: url) != nil }

    public func parse(url: URL) throws -> ParsedDocument {
        guard let parser = parser(for: url) else { throw ParserError.unsupported(url.lastPathComponent) }
        return try parser.parse(url: url)
    }
}
