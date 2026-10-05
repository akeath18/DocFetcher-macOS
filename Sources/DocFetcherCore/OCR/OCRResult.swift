import Foundation

public struct OCRResult: Sendable, Equatable {
    /// Text exactly as recognised.
    public var rawText: String
    /// Text after erroneous-symbol cleanup.
    public var cleanedText: String
    /// Mean engine confidence (0...1), or a heuristic quality score when the engine gives none.
    public var confidence: Double
    public var pageConfidences: [Double]
    public var removedSymbolCount: Int

    public init(rawText: String, cleanedText: String, confidence: Double, pageConfidences: [Double] = [],
                removedSymbolCount: Int = 0) {
        self.rawText = rawText
        self.cleanedText = cleanedText
        self.confidence = confidence
        self.pageConfidences = pageConfidences
        self.removedSymbolCount = removedSymbolCount
    }

    /// Returns the original or cleaned text, supporting an original/cleaned toggle in the UI.
    public func text(cleaned: Bool) -> String { cleaned ? cleanedText : rawText }
}
