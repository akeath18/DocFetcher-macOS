import Foundation

public struct EPUBParser: DocumentParser {
    public let name = "EPUB"
    public let supportedExtensions: Set<String> = ["epub"]
    public init() {}

    public func parse(url: URL) throws -> ParsedDocument {
        let zip = ZipArchive(url: url)
        guard let entries = try? zip.entries(), !entries.isEmpty else { throw ParserError.corrupted("invalid EPUB archive") }
        var metadata = DocumentMetadata()
        if let opfPath = entries.first(where: { $0.hasSuffix(".opf") }), let opf = try? zip.read(opfPath) {
            let v = XMLLeafCollector.collect(opf)
            metadata.title = v["title"]
            metadata.author = v["creator"]
            metadata.created = DateParsing.parse(v["date"])
        }
        let chapters = OfficeParser.naturalSort(entries.filter {
            let l = $0.lowercased()
            return l.hasSuffix(".xhtml") || l.hasSuffix(".html") || l.hasSuffix(".htm")
        })
        guard !chapters.isEmpty else { throw ParserError.corrupted("EPUB has no content documents") }
        var text: [String] = []
        for chapter in chapters {
            guard let data = try? zip.read(chapter) else { continue }
            text.append(HTMLParser.parse(html: TextParser.decode(data)).text)
        }
        return ParsedDocument(text: text.joined(separator: "\n\n"), metadata: metadata)
    }
}

public struct SVGParser: DocumentParser {
    public let name = "SVG"
    public let supportedExtensions: Set<String> = ["svg"]
    public init() {}

    public func parse(url: URL) throws -> ParsedDocument {
        guard let data = try? Data(contentsOf: url) else { throw ParserError.unreadable(url.lastPathComponent) }
        let text = XMLTextExtractor.extract(data, textElements: ["text", "title", "desc"], breakElements: ["text", "title", "desc"])
        let title = XMLLeafCollector.collect(data)["title"]
        return ParsedDocument(text: HTMLParser.normalizeWhitespace(text), metadata: DocumentMetadata(title: title))
    }
}
