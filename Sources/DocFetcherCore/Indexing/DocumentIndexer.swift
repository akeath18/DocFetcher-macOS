import Foundation

public enum IndexOutcome: Sendable, Equatable {
    case indexed, unchanged, failed(String), unsupported
}

public struct IndexProgress: Sendable {
    public var processed: Int
    public var total: Int
    public var currentFile: String
}

public struct IndexSummary: Sendable, Equatable {
    public var indexed = 0
    public var unchanged = 0
    public var failed = 0
    public var removed = 0
}

/// Parses files and writes them to the index. Only new or modified files are re-parsed (incremental indexing).
public final class DocumentIndexer: @unchecked Sendable {
    private let database: IndexDatabase
    private let registry: ParserRegistry
    private let ocr: OCRProcessor?
    /// Cap on indexed text per document to bound memory use.
    public var maxContentLength = 10_000_000
    public var maxConcurrency = max(1, min(ProcessInfo.processInfo.activeProcessorCount, 4))

    public init(database: IndexDatabase, registry: ParserRegistry = .shared, ocr: OCRProcessor? = nil) {
        self.database = database
        self.registry = registry
        self.ocr = ocr
    }

    public func indexFile(_ url: URL, force: Bool = false) async -> IndexOutcome {
        guard registry.canParse(url) else { return .unsupported }
        let path = url.standardizedFileURL.path
        let modified = FileUtils.modificationDate(url)
        let size = FileUtils.fileSize(url)
        if !force, let existing = try? database.document(path: path),
           abs(existing.modified.timeIntervalSince(modified)) < 0.001, existing.size == size {
            return .unchanged
        }
        do {
            var parsed = try registry.parse(url: url)
            var ocrText: String?
            var ocrConfidence: Double?
            var useOCR = false
            if parsed.needsOCR, let ocr, let result = try? await ocr.recognize(url: url), !result.cleanedText.isEmpty {
                ocrText = result.cleanedText
                ocrConfidence = result.confidence
                useOCR = parsed.text.filter { !$0.isWhitespace }.count < result.cleanedText.filter { !$0.isWhitespace }.count
            }
            if parsed.text.count > maxContentLength { parsed.text = String(parsed.text.prefix(maxContentLength)) }
            var metadata = parsed.metadata
            if metadata.modified == nil { metadata.modified = modified }
            let doc = IndexableDocument(
                path: path, filename: url.lastPathComponent, fileExtension: url.pathExtension.lowercased(),
                mimeType: MIMETypeDetector.detect(url: url), size: size, modified: modified, metadata: metadata,
                content: parsed.text, ocrText: ocrText, ocrConfidence: ocrConfidence, useOCR: useOCR)
            try database.upsert(doc)
            try? database.clearError(path: path)
            return .indexed
        } catch {
            let message = "\(error)"
            try? database.recordError(path: path, message: message)
            Log.error("Failed to index \(path): \(message)")
            return .failed(message)
        }
    }

    /// Indexes everything below `folder`, removes entries for deleted files, and reports progress.
    public func indexFolder(_ folder: URL, progress: (@Sendable (IndexProgress) -> Void)? = nil) async -> IndexSummary {
        let root = folder.standardizedFileURL
        let files = FileUtils.enumerateFiles(in: root).filter { registry.canParse($0) }
        var summary = IndexSummary()
        var processed = 0

        await withTaskGroup(of: IndexOutcome.self) { group in
            var iterator = files.makeIterator()
            func addNext() -> Bool {
                guard let url = iterator.next() else { return false }
                progress?(IndexProgress(processed: processed, total: files.count, currentFile: url.lastPathComponent))
                group.addTask { await self.indexFile(url) }
                return true
            }
            for _ in 0..<maxConcurrency { if !addNext() { break } }
            while let outcome = await group.next() {
                processed += 1
                switch outcome {
                case .indexed: summary.indexed += 1
                case .unchanged: summary.unchanged += 1
                case .failed: summary.failed += 1
                case .unsupported: break
                }
                if Task.isCancelled { group.cancelAll(); continue }
                _ = addNext()
            }
        }
        if !Task.isCancelled {
            summary.removed = removeMissingFiles(under: root)
        }
        progress?(IndexProgress(processed: processed, total: files.count, currentFile: ""))
        return summary
    }

    @discardableResult
    public func removeMissingFiles(under root: URL) -> Int {
        let prefix = root.standardizedFileURL.path.hasSuffix("/") ? root.standardizedFileURL.path : root.standardizedFileURL.path + "/"
        var removed = 0
        for path in (try? database.filePaths(under: prefix)) ?? [] where !FileManager.default.fileExists(atPath: path) {
            try? database.deleteDocument(path: path)
            removed += 1
        }
        return removed
    }
}
