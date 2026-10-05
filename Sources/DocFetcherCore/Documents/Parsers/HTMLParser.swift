import Foundation

public struct HTMLParser: DocumentParser {
    public let name = "HTML"
    public let supportedExtensions: Set<String> = ["html", "htm", "xhtml"]
    public init() {}

    public func parse(url: URL) throws -> ParsedDocument {
        guard let data = try? Data(contentsOf: url) else { throw ParserError.unreadable(url.lastPathComponent) }
        return Self.parse(html: TextParser.decode(data))
    }

    static func parse(html: String) -> ParsedDocument {
        var metadata = DocumentMetadata()
        metadata.title = firstMatch(#"<title[^>]*>(.*?)</title>"#, in: html).map(clean)
        metadata.author = firstMatch(#"<meta[^>]+name\s*=\s*["']author["'][^>]*content\s*=\s*["']([^"']*)["']"#, in: html)
            .map(decodeEntities)
        var body = html
        for tag in ["script", "style", "head", "noscript"] {
            body = replace("<\(tag)\\b[^>]*>.*?</\(tag)\\s*>", in: body, with: " ")
        }
        body = replace("<!--.*?-->", in: body, with: " ")
        body = replace("<(br|/p|/div|/li|/tr|/h[1-6]|/table|/section|/article)\\b[^>]*>", in: body, with: "\n")
        body = replace("<[^>]+>", in: body, with: " ")
        return ParsedDocument(text: normalizeWhitespace(decodeEntities(body)), metadata: metadata)
    }

    private static func clean(_ s: String) -> String { normalizeWhitespace(decodeEntities(s)) }

    private static func firstMatch(_ pattern: String, in s: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: s) else { return nil }
        let value = String(s[r])
        return value.isEmpty ? nil : value
    }

    private static func replace(_ pattern: String, in s: String, with template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }

    static func normalizeWhitespace(_ s: String) -> String {
        s.components(separatedBy: "\n")
            .map { $0.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\u{A0}" || $0 == "\r" }).joined(separator: " ") }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "copy": "©", "reg": "®",
        "mdash": "—", "ndash": "–", "hellip": "…", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”",
    ]

    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&"), let re = try? NSRegularExpression(pattern: "&(#x?[0-9A-Fa-f]+|[A-Za-z]+);") else { return s }
        var out = ""
        var last = s.startIndex
        for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            guard let whole = Range(m.range, in: s), let inner = Range(m.range(at: 1), in: s) else { continue }
            out += s[last..<whole.lowerBound]
            let e = String(s[inner])
            if e.hasPrefix("#") {
                let hex = e.dropFirst().first == "x" || e.dropFirst().first == "X"
                let digits = e.dropFirst(hex ? 2 : 1)
                if let v = UInt32(digits, radix: hex ? 16 : 10), let scalar = Unicode.Scalar(v) { out.unicodeScalars.append(scalar) }
            } else if let r = named[e.lowercased()] {
                out += r
            } else {
                out += s[whole]
            }
            last = whole.upperBound
        }
        out += s[last...]
        return out
    }
}
