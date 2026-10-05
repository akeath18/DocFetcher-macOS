import Foundation

public struct TextParser: DocumentParser {
    public let name = "Plain text"
    public let supportedExtensions: Set<String> = [
        "txt", "text", "md", "markdown", "csv", "tsv", "log", "json", "yaml", "yml", "ini", "conf", "swift",
        "py", "js", "ts", "java", "c", "h", "cpp", "m", "go", "rs", "sh", "tex", "srt",
    ]
    public init() {}

    public func parse(url: URL) throws -> ParsedDocument {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            throw ParserError.unreadable(url.lastPathComponent)
        }
        return ParsedDocument(text: Self.decode(data), metadata: .init())
    }

    /// Decodes bytes using BOM detection, then UTF-8, then a legacy 8-bit fallback.
    static func decode(_ data: Data) -> String {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let s = String(data: data, encoding: .utf16) { return s }
        if data.starts(with: [0xEF, 0xBB, 0xBF]), let s = String(data: data.dropFirst(3), encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .utf8) { return s }
        return String(data: data, encoding: .isoLatin1) ?? String(decoding: data, as: UTF8.self)
    }
}
