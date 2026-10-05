import Foundation

/// A document stored in (or about to be stored in) the search index.
public struct IndexableDocument: Equatable, Sendable {
    public var id: Int64?
    public var path: String
    public var filename: String
    public var fileExtension: String
    public var mimeType: String
    public var size: Int64
    public var modified: Date
    public var indexedAt: Date
    public var metadata: DocumentMetadata
    /// Text extracted directly from the document.
    public var content: String
    /// Cleaned OCR text, when the document was scanned.
    public var ocrText: String?
    public var ocrConfidence: Double?
    /// When true and `ocrText` exists, the OCR text is what gets searched.
    public var useOCR: Bool
    public var kind: DocumentKind

    public init(id: Int64? = nil, path: String, filename: String, fileExtension: String, mimeType: String,
                size: Int64, modified: Date, indexedAt: Date = Date(), metadata: DocumentMetadata = .init(),
                content: String, ocrText: String? = nil, ocrConfidence: Double? = nil, useOCR: Bool = false,
                kind: DocumentKind = .file) {
        self.id = id
        self.path = path
        self.filename = filename
        self.fileExtension = fileExtension
        self.mimeType = mimeType
        self.size = size
        self.modified = modified
        self.indexedAt = indexedAt
        self.metadata = metadata
        self.content = content
        self.ocrText = ocrText
        self.ocrConfidence = ocrConfidence
        self.useOCR = useOCR
        self.kind = kind
    }

    /// The text that is searched and previewed.
    public var effectiveText: String {
        if useOCR, let ocr = ocrText { return ocr }
        return content
    }
}
