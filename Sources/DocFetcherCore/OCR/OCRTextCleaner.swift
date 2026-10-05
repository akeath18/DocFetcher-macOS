import Foundation

/// Removes characters and lines that are typically OCR noise, and scores text quality.
public enum OCRTextCleaner {
    private static let noiseCharacters: Set<Character> = ["|", "~", "^", "`", "\\", "¦", "�", "§", "¬", "■", "□", "◊", "¨"]
    private static let ligatures: [String: String] = ["ﬁ": "fi", "ﬂ": "fl", "ﬀ": "ff", "ﬃ": "ffi", "ﬄ": "ffl"]

    public static func clean(_ text: String) -> (text: String, removed: Int) {
        var removed = 0
        var s = text
        for (k, v) in ligatures { s = s.replacingOccurrences(of: k, with: v) }
        // Re-join words hyphenated across line breaks.
        if let re = try? NSRegularExpression(pattern: #"([A-Za-z]{2,})-\n([a-z]{2,})"#) {
            s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "$1$2")
        }
        var lines: [String] = []
        for rawLine in s.components(separatedBy: "\n") {
            var line = ""
            for ch in rawLine {
                if noiseCharacters.contains(ch) || ch.unicodeScalars.contains(where: { $0.properties.generalCategory == .control && $0 != "\t" }) {
                    removed += 1
                } else { line.append(ch) }
            }
            // Drop isolated single symbols surrounded by spaces, and long runs of repeated punctuation.
            var tokens: [String] = []
            for token in line.split(separator: " ", omittingEmptySubsequences: true) {
                if token.count == 1, let c = token.first, !c.isLetter, !c.isNumber, !".,;:!?()-–—\"'%$€£&@#/+=".contains(c) {
                    removed += 1; continue
                }
                if token.count >= 4, Set(token).count == 1, let c = token.first, !c.isLetter, !c.isNumber, c != "." || token.count > 6 {
                    removed += token.count; continue
                }
                tokens.append(String(token))
            }
            let cleaned = tokens.joined(separator: " ")
            let alnum = cleaned.filter { $0.isLetter || $0.isNumber }.count
            let visible = cleaned.filter { !$0.isWhitespace }.count
            // A line that is mostly symbols is noise (scan borders, specks).
            if visible > 0, Double(alnum) / Double(visible) < 0.4, visible < 40 {
                removed += visible; continue
            }
            lines.append(cleaned)
        }
        var result = lines.joined(separator: "\n")
        if let re = try? NSRegularExpression(pattern: "\n{3,}") {
            result = re.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "\n\n")
        }
        return (result.trimmingCharacters(in: .whitespacesAndNewlines), removed)
    }

    /// Heuristic 0...1 score: share of tokens that look like real words or numbers.
    public static func qualityScore(_ text: String) -> Double {
        let tokens = text.split(whereSeparator: { $0.isWhitespace })
        guard !tokens.isEmpty else { return 0 }
        let good = tokens.filter { token in
            let letters = token.filter { $0.isLetter }.count
            let digits = token.filter { $0.isNumber }.count
            let other = token.count - letters - digits
            guard letters + digits > 0, other <= max(token.count / 3, 2) else { return false }
            let vowels = token.lowercased().filter { "aeiouyàáâãäåèéêëìíîïòóôõöùúûü".contains($0) }.count
            return letters < 5 || vowels > 0
        }.count
        return Double(good) / Double(tokens.count)
    }

    public static func makeResult(rawText: String, engineConfidence: Double?, pageConfidences: [Double] = []) -> OCRResult {
        let (cleaned, removed) = clean(rawText)
        let quality = qualityScore(cleaned)
        let confidence = engineConfidence.map { ($0 + quality) / 2 } ?? quality
        return OCRResult(rawText: rawText, cleanedText: cleaned, confidence: confidence,
                         pageConfidences: pageConfidences, removedSymbolCount: removed)
    }
}
