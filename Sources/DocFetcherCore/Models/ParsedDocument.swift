import Foundation

/// Output of a `DocumentParser`.
public struct ParsedDocument: Sendable {
    public var text: String
    public var metadata: DocumentMetadata
    /// True when the file looks like a scan (little or no embedded text) and OCR should be attempted.
    public var needsOCR: Bool

    public init(text: String, metadata: DocumentMetadata = .init(), needsOCR: Bool = false) {
        self.text = text
        self.metadata = metadata
        self.needsOCR = needsOCR
    }
}

public enum ParserError: Error, CustomStringConvertible {
    case unsupported(String)
    case corrupted(String)
    case unreadable(String)
    case toolUnavailable(String)

    public var description: String {
        switch self {
        case .unsupported(let m): return "Unsupported: \(m)"
        case .corrupted(let m): return "Corrupted: \(m)"
        case .unreadable(let m): return "Unreadable: \(m)"
        case .toolUnavailable(let m): return "Tool unavailable: \(m)"
        }
    }
}
