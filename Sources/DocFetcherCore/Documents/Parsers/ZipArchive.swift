import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Reads ZIP entries via the system `unzip` tool without extracting to disk.
struct ZipArchive {
    let url: URL

    func entries() throws -> [String] {
        let data = try FileUtils.runTool(["unzip", "-Z1", url.path])
        return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
    }

    func read(_ entry: String, maxSize: Int = 64 * 1024 * 1024) throws -> Data {
        // unzip treats [ ] * ? as wildcards; escape them to match the literal entry name.
        var escaped = ""
        for ch in entry {
            if "[]*?\\".contains(ch) { escaped.append("\\") }
            escaped.append(ch)
        }
        return try FileUtils.runTool(["unzip", "-p", url.path, escaped], maxOutput: maxSize)
    }
}

/// Collects text from selected XML elements; used for OOXML, ODF, SVG and XHTML.
final class XMLTextExtractor: NSObject, XMLParserDelegate {
    private let textElements: Set<String>
    private let breakElements: Set<String>
    private var depth = 0
    private(set) var text = ""

    init(textElements: Set<String>, breakElements: Set<String>) {
        self.textElements = textElements
        self.breakElements = breakElements
    }

    static func extract(_ data: Data, textElements: Set<String>, breakElements: Set<String>) -> String {
        let ex = XMLTextExtractor(textElements: textElements, breakElements: breakElements)
        let parser = XMLParser(data: data)
        parser.delegate = ex
        parser.shouldResolveExternalEntities = false
        parser.parse()  // best effort: keep whatever was extracted even if the XML is malformed
        return ex.text
    }

    private func local(_ n: String) -> String { n.split(separator: ":").last.map(String.init) ?? n }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if textElements.contains(local(elementName)) { depth += 1 }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if depth > 0 { text += string } }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let n = local(elementName)
        if textElements.contains(n) { depth -= 1 }
        if breakElements.contains(n) { text += "\n" }
    }
}

/// Collects leaf element text keyed by local name (for docProps/core.xml and ODF meta.xml).
final class XMLLeafCollector: NSObject, XMLParserDelegate {
    private(set) var values: [String: String] = [:]
    private var current = ""
    private var buffer = ""

    static func collect(_ data: Data) -> [String: String] {
        let c = XMLLeafCollector()
        let parser = XMLParser(data: data)
        parser.delegate = c
        parser.shouldResolveExternalEntities = false
        parser.parse()
        return c.values
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        current = elementName.split(separator: ":").last.map(String.init) ?? elementName
        buffer = ""
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { buffer += string }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        let v = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if name == current, !v.isEmpty, values[name] == nil { values[name] = v }
        buffer = ""
        current = ""
    }
}

enum DateParsing {
    static func parse(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        for fmt in ["yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"] {
            df.dateFormat = fmt
            if let d = df.date(from: s) { return d }
        }
        return nil
    }
}
