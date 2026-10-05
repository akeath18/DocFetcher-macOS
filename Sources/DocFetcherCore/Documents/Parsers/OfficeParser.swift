import Foundation

/// OOXML (docx/xlsx/pptx) and OpenDocument (odt/ods/odp/odg) parser, implemented natively on top of ZIP + XML.
public struct OfficeParser: DocumentParser {
    public let name = "Office / OpenDocument"
    public let supportedExtensions: Set<String> = ["docx", "xlsx", "pptx", "docm", "xlsm", "pptm", "odt", "ods", "odp", "odg", "ott", "ots", "otp", "fodt"]
    public init() {}

    public func parse(url: URL) throws -> ParsedDocument {
        let ext = url.pathExtension.lowercased()
        let zip = ZipArchive(url: url)
        let entries: [String]
        do { entries = try zip.entries() } catch { throw ParserError.corrupted("not a valid archive: \(url.lastPathComponent)") }
        guard !entries.isEmpty else { throw ParserError.corrupted("empty archive") }

        var parts: [String] = []
        var metadata = DocumentMetadata()
        if entries.contains("content.xml") {
            guard let data = try? zip.read("content.xml") else { throw ParserError.corrupted("missing content.xml") }
            parts.append(XMLTextExtractor.extract(data, textElements: ["p", "h"], breakElements: ["p", "h"]))
            if let meta = try? zip.read("meta.xml") { metadata = Self.odfMetadata(meta) }
        } else {
            let wanted: [String]
            switch ext.prefix(2) {
            case "do": wanted = entries.filter { $0 == "word/document.xml" || $0.hasPrefix("word/footnotes") || $0.hasPrefix("word/endnotes") }
            case "xl": wanted = entries.filter { $0 == "xl/sharedStrings.xml" || ($0.hasPrefix("xl/worksheets/") && $0.hasSuffix(".xml")) }
            default: wanted = entries.filter { ($0.hasPrefix("ppt/slides/slide") || $0.hasPrefix("ppt/notesSlides/notesSlide")) && $0.hasSuffix(".xml") }
            }
            guard !wanted.isEmpty else { throw ParserError.corrupted("no document content found") }
            for entry in Self.naturalSort(wanted) {
                guard let data = try? zip.read(entry) else { continue }
                let breaks: Set<String> = entry.contains("sharedStrings") ? ["si"] : ["p", "br", "si", "row"]
                parts.append(XMLTextExtractor.extract(data, textElements: ["t"], breakElements: breaks))
            }
            if let core = try? zip.read("docProps/core.xml") { metadata = Self.ooxmlMetadata(core) }
            if ext.hasPrefix("pp") { metadata.pageCount = wanted.filter { $0.hasPrefix("ppt/slides/") }.count }
        }
        return ParsedDocument(text: HTMLParser.normalizeWhitespace(parts.joined(separator: "\n")), metadata: metadata)
    }

    static func naturalSort(_ a: [String]) -> [String] {
        a.sorted { $0.compare($1, options: .numeric) == .orderedAscending }
    }

    static func ooxmlMetadata(_ data: Data) -> DocumentMetadata {
        let v = XMLLeafCollector.collect(data)
        return DocumentMetadata(title: v["title"], author: v["creator"], created: DateParsing.parse(v["created"]),
                                modified: DateParsing.parse(v["modified"]))
    }

    static func odfMetadata(_ data: Data) -> DocumentMetadata {
        let v = XMLLeafCollector.collect(data)
        return DocumentMetadata(title: v["title"], author: v["creator"] ?? v["initial-creator"],
                                created: DateParsing.parse(v["creation-date"]), modified: DateParsing.parse(v["date"]))
    }
}

/// Legacy binary Office formats (doc/xls/ppt). Uses macOS `textutil` for .doc when available,
/// otherwise falls back to extracting printable strings from the OLE container.
public struct LegacyOfficeParser: DocumentParser {
    public let name = "Legacy Office"
    public let supportedExtensions: Set<String> = ["doc", "xls", "ppt", "chm"]
    public init() {}

    public func parse(url: URL) throws -> ParsedDocument {
        let ext = url.pathExtension.lowercased()
        if ext == "doc", FileManager.default.fileExists(atPath: "/usr/bin/textutil"),
           let data = try? FileUtils.runTool(["textutil", "-convert", "txt", "-stdout", url.path]), !data.isEmpty {
            return ParsedDocument(text: HTMLParser.normalizeWhitespace(TextParser.decode(data)))
        }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count > 8 else {
            throw ParserError.unreadable(url.lastPathComponent)
        }
        if ext != "chm", !data.starts(with: [0xD0, 0xCF, 0x11, 0xE0]) { throw ParserError.corrupted("not an OLE document") }
        let text = Self.printableStrings(in: data)
        guard !text.isEmpty else { throw ParserError.corrupted("no text found") }
        return ParsedDocument(text: text)
    }

    /// Extracts ASCII and UTF-16LE runs of at least 6 printable characters.
    static func printableStrings(in data: Data, minLength: Int = 6) -> String {
        let bytes = [UInt8](data)
        var runs: [String] = []
        func isPrintable(_ b: UInt8) -> Bool { (b >= 0x20 && b < 0x7F) || b == 0x09 }
        var cur = [UInt8]()
        for b in bytes {
            if isPrintable(b) { cur.append(b) } else {
                if cur.count >= minLength { runs.append(String(decoding: cur, as: UTF8.self)) }
                cur.removeAll(keepingCapacity: true)
            }
        }
        if cur.count >= minLength { runs.append(String(decoding: cur, as: UTF8.self)) }
        var i = 0
        var wide = [UInt8]()
        while i + 1 < bytes.count {
            if isPrintable(bytes[i]) && bytes[i + 1] == 0 { wide.append(bytes[i]); i += 2 } else {
                if wide.count >= minLength { runs.append(String(decoding: wide, as: UTF8.self)) }
                wide.removeAll(keepingCapacity: true)
                i += 1
            }
        }
        if wide.count >= minLength { runs.append(String(decoding: wide, as: UTF8.self)) }
        return runs.joined(separator: "\n")
    }
}
