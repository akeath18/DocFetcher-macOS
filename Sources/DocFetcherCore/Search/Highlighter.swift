import Foundation

/// Locates query matches inside document text, enabling highlighting in previews.
public enum Highlighter {
    /// Returns NSRange (UTF-16) matches of any term, case- and diacritic-insensitively.
    public static func ranges(of terms: [String], in text: String, limit: Int = 500) -> [NSRange] {
        var result: [NSRange] = []
        let ns = text as NSString
        for term in Set(terms.filter { !$0.isEmpty }) {
            var searchRange = NSRange(location: 0, length: ns.length)
            while searchRange.length > 0, result.count < limit {
                let r = ns.range(of: term, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange)
                if r.location == NSNotFound { break }
                result.append(r)
                let next = r.location + max(r.length, 1)
                searchRange = NSRange(location: next, length: ns.length - next)
            }
        }
        return result.sorted { $0.location < $1.location }
    }

    /// Builds a context snippet of roughly `width` characters around the first match.
    public static func snippet(in text: String, terms: [String], width: Int = 160) -> (String, [NSRange]) {
        let ns = text as NSString
        let matches = ranges(of: terms, in: text, limit: 50)
        let start = max((matches.first?.location ?? 0) - width / 3, 0)
        let length = min(width, ns.length - start)
        guard length > 0 else { return ("", []) }
        var window = NSRange(location: start, length: length)
        window = ns.rangeOfComposedCharacterSequences(for: window)
        let slice = ns.substring(with: window).replacingOccurrences(of: "\n", with: " ")
        let shifted = matches.compactMap { m -> NSRange? in
            guard m.location >= window.location, NSMaxRange(m) <= NSMaxRange(window) else { return nil }
            return NSRange(location: m.location - window.location, length: m.length)
        }
        return ((start > 0 ? "…" : "") + slice, shifted.map {
            NSRange(location: $0.location + (start > 0 ? 1 : 0), length: $0.length)
        })
    }
}
