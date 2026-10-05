import Foundation

/// Minimal RTF-to-text converter (control words, groups, hex and unicode escapes).
public struct RTFParser: DocumentParser {
    public let name = "RTF"
    public let supportedExtensions: Set<String> = ["rtf"]
    public init() {}

    public func parse(url: URL) throws -> ParsedDocument {
        guard let data = try? Data(contentsOf: url) else { throw ParserError.unreadable(url.lastPathComponent) }
        guard data.starts(with: Array("{\\rtf".utf8)) else { throw ParserError.corrupted("not an RTF file") }
        return ParsedDocument(text: Self.extractText(from: [UInt8](data)))
    }

    private static let skipDestinations: Set<String> = [
        "fonttbl", "colortbl", "stylesheet", "info", "pict", "header", "footer", "themedata", "colorschememapping",
        "latentstyles", "datastore", "generator", "listtable", "listoverridetable", "rsidtbl", "object",
    ]

    static func extractText(from b: [UInt8]) -> String {
        var out = [UInt16]()
        var stack: [(skip: Bool, uc: Int)] = []
        var skip = false
        var uc = 1
        var pendingSkipChars = 0
        var i = 0
        func emit(_ u: UInt16) { if !skip { out.append(u) } }
        while i < b.count {
            let c = b[i]
            switch c {
            case UInt8(ascii: "{"):
                stack.append((skip, uc)); i += 1
            case UInt8(ascii: "}"):
                if let top = stack.popLast() { skip = top.skip; uc = top.uc }
                i += 1
            case UInt8(ascii: "\\"):
                i += 1
                guard i < b.count else { break }
                let n = b[i]
                if n == UInt8(ascii: "'") {
                    if i + 2 < b.count, let v = UInt8(String(decoding: b[(i + 1)...(i + 2)], as: UTF8.self), radix: 16) {
                        if pendingSkipChars > 0 { pendingSkipChars -= 1 } else { emit(cp1252(v)) }
                        i += 3
                    } else { i += 1 }
                } else if n == UInt8(ascii: "*") {
                    skip = true; i += 1
                } else if (n >= 65 && n <= 90) || (n >= 97 && n <= 122) {
                    var j = i
                    while j < b.count, (b[j] >= 65 && b[j] <= 90) || (b[j] >= 97 && b[j] <= 122) { j += 1 }
                    let word = String(decoding: b[i..<j], as: UTF8.self)
                    var k = j
                    if k < b.count, b[k] == UInt8(ascii: "-") { k += 1 }
                    while k < b.count, b[k] >= 48 && b[k] <= 57 { k += 1 }
                    let param = Int(String(decoding: b[j..<k], as: UTF8.self))
                    if k < b.count, b[k] == UInt8(ascii: " ") { k += 1 }
                    i = k
                    switch word {
                    case "par", "line", "sect", "page": emit(10)
                    case "tab": emit(9)
                    case "emdash": emit(0x2014)
                    case "endash": emit(0x2013)
                    case "bullet": emit(0x2022)
                    case "lquote": emit(0x2018)
                    case "rquote": emit(0x2019)
                    case "ldblquote": emit(0x201C)
                    case "rdblquote": emit(0x201D)
                    case "uc": uc = param ?? 1
                    case "u":
                        if let p = param { emit(UInt16(truncatingIfNeeded: p < 0 ? p + 65536 : p)); pendingSkipChars = uc }
                    default:
                        if skipDestinations.contains(word) { skip = true }
                    }
                } else {
                    switch n {
                    case UInt8(ascii: "~"): emit(0xA0)
                    case UInt8(ascii: "\\"), UInt8(ascii: "{"), UInt8(ascii: "}"): emit(UInt16(n))
                    default: break
                    }
                    i += 1
                }
            case 10, 13:
                i += 1
            default:
                if pendingSkipChars > 0 { pendingSkipChars -= 1 }
                else if c < 0x80 { emit(UInt16(c)) }
                else { emit(cp1252(c)) }
                i += 1
            }
        }
        return HTMLParser.normalizeWhitespace(String(decoding: out, as: UTF16.self))
    }

    private static func cp1252(_ v: UInt8) -> UInt16 {
        let table: [UInt8: UInt16] = [0x80: 0x20AC, 0x85: 0x2026, 0x91: 0x2018, 0x92: 0x2019, 0x93: 0x201C,
                                      0x94: 0x201D, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014, 0x99: 0x2122]
        return table[v] ?? UInt16(v)
    }
}
