import Foundation

public enum SortOrder: String, CaseIterable, Codable, Sendable {
    case relevance, filename, dateModified, fileSize
}

public struct SearchFilters: Equatable, Sendable {
    public var extensions: Set<String>
    public var modifiedAfter: Date?
    public var modifiedBefore: Date?
    public init(extensions: Set<String> = [], modifiedAfter: Date? = nil, modifiedBefore: Date? = nil) {
        self.extensions = Set(extensions.map { $0.lowercased() })
        self.modifiedAfter = modifiedAfter
        self.modifiedBefore = modifiedBefore
    }
}

/// A parsed user query. Supported syntax:
/// - words (implicit AND), `AND`, `OR`, `NOT`, `-word`
/// - `"exact phrase"`, `prefix*`, parentheses
/// - fields: `filename:`, `title:`, `author:`, `content:`
/// - filters: `type:pdf`, `after:2024-01-31`, `before:2024-12-31`
public struct SearchQuery: Equatable, Sendable {
    enum Token: Equatable {
        case term(field: String?, text: String, prefix: Bool)
        case phrase(field: String?, text: String)
        case and, or, not, open, close
    }

    static let ftsFields: Set<String> = ["filename", "title", "author", "content"]

    public let raw: String
    let tokens: [Token]
    public private(set) var filters: SearchFilters

    public init(_ raw: String) {
        self.raw = raw
        var filters = SearchFilters()
        var tokens: [Token] = []
        for piece in Self.tokenize(raw) {
            switch piece {
            case .word(let w): Self.handleWord(w, quoted: false, into: &tokens, filters: &filters)
            case .quoted(let q): Self.handleWord(q, quoted: true, into: &tokens, filters: &filters)
            case .open: tokens.append(.open)
            case .close: tokens.append(.close)
            }
        }
        self.tokens = tokens
        self.filters = filters
    }

    /// True when the query contains no searchable terms (only filters, or nothing).
    public var isEmpty: Bool { ftsExpression() == nil }

    /// Plain-text words usable for highlighting (excludes negated terms).
    public var highlightTerms: [String] {
        var out: [String] = []
        var negate = false
        for t in tokens {
            switch t {
            case .not: negate = true; continue
            case .term(_, let text, _): if !negate { out.append(text) }
            case .phrase(_, let text): if !negate { out.append(text) }
            default: break
            }
            negate = false
        }
        return out
    }

    /// Builds an FTS5 MATCH expression, or nil if there is nothing to match.
    /// `expand` may return additional spellings for a term (fuzzy matching).
    /// FTS5's NOT is binary, so a negation with no left-hand operand is ignored.
    public func ftsExpression(expand: ((String) -> [String])? = nil) -> String? {
        func quote(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        func field(_ f: String?, _ expr: String) -> String { f.map { "\($0) : \(expr)" } ?? expr }
        let operators: Set<String> = ["AND", "OR", "NOT"]

        var parts: [String] = []
        var depth = 0
        var skipOperand = false
        func prevIsOperand() -> Bool {
            guard let last = parts.last else { return false }
            return !operators.contains(last) && last != "("
        }
        func add(operand: String) {
            if skipOperand { skipOperand = false; return }
            if prevIsOperand() { parts.append("AND") }
            parts.append(operand)
        }

        for token in tokens {
            switch token {
            case .term(let f, let text, let prefix):
                var expr = quote(text)
                if prefix { expr = "(" + expr + " *)" }
                else if let variants = expand?(text), !variants.isEmpty {
                    expr = "(" + ([text] + variants).map(quote).joined(separator: " OR ") + ")"
                }
                add(operand: field(f, expr))
            case .phrase(let f, let text):
                add(operand: field(f, quote(text)))
            case .and, .or:
                if prevIsOperand() { parts.append(token == .and ? "AND" : "OR") }
            case .not:
                if let last = parts.last, last == "AND" || last == "OR" { parts.removeLast() }
                if prevIsOperand() { parts.append("NOT") } else { skipOperand = true }
            case .open:
                if prevIsOperand() { parts.append("AND") }
                parts.append("("); depth += 1
            case .close:
                if depth > 0 && prevIsOperand() { parts.append(")"); depth -= 1 }
            }
        }
        while let last = parts.last, operators.contains(last) || last == "(" {
            if last == "(" { depth -= 1 }
            parts.removeLast()
        }
        guard parts.contains(where: { !operators.contains($0) && $0 != "(" && $0 != ")" }) else { return nil }
        parts.append(contentsOf: Array(repeating: ")", count: max(depth, 0)))
        return parts.joined(separator: " ")
    }

    // MARK: Parsing helpers

    private enum Piece { case word(String), quoted(String), open, close }

    private static func tokenize(_ s: String) -> [Piece] {
        var pieces: [Piece] = []
        var current = ""
        var inQuote = false
        var fieldPrefix = ""
        func flush() {
            if !current.isEmpty || !fieldPrefix.isEmpty { pieces.append(.word(fieldPrefix + current)) }
            current = ""; fieldPrefix = ""
        }
        for ch in s {
            if inQuote {
                if ch == "\"" {
                    pieces.append(.quoted(fieldPrefix + current))
                    current = ""; fieldPrefix = ""; inQuote = false
                } else { current.append(ch) }
            } else if ch == "\"" {
                if current.hasSuffix(":") && !current.dropLast().isEmpty { fieldPrefix = current; current = "" }
                else { flush() }
                inQuote = true
            } else if ch.isWhitespace {
                flush()
            } else if ch == "(" || ch == ")" {
                flush()
                pieces.append(ch == "(" ? .open : .close)
            } else {
                current.append(ch)
            }
        }
        if inQuote { pieces.append(.quoted(fieldPrefix + current)) } else { flush() }
        return pieces
    }

    private static func handleWord(_ word: String, quoted: Bool, into tokens: inout [Token], filters: inout SearchFilters) {
        var w = word
        var negated = false
        if !quoted, w.hasPrefix("-"), w.count > 1 { negated = true; w.removeFirst() }
        if !quoted {
            switch w {
            case "AND": tokens.append(.and); return
            case "OR": tokens.append(.or); return
            case "NOT": tokens.append(.not); return
            default: break
            }
        }
        var field: String?
        if let colon = w.firstIndex(of: ":"), colon != w.startIndex {
            let name = w[w.startIndex..<colon].lowercased()
            let value = String(w[w.index(after: colon)...])
            if ftsFields.contains(name) { field = name; w = value }
            else if !value.isEmpty, name == "type" || name == "ext" {
                filters.extensions.insert(value.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")))
                return
            } else if !value.isEmpty, name == "after" || name == "before", let d = parseDate(value) {
                if name == "after" { filters.modifiedAfter = d }
                else { filters.modifiedBefore = d.addingTimeInterval(86_399) }
                return
            }
        }
        if negated { tokens.append(.not) }
        if quoted {
            if !w.isEmpty { tokens.append(.phrase(field: field, text: w)) }
            return
        }
        var prefix = false
        if w.hasSuffix("*") { prefix = true; w.removeLast() }
        // Keep only text FTS5's tokenizer would see; skip pure punctuation.
        guard w.contains(where: { $0.isLetter || $0.isNumber }) else {
            if negated { tokens.removeLast() }
            return
        }
        tokens.append(.term(field: field, text: w, prefix: prefix))
    }

    static func parseDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }
}
