import Foundation

public struct IndexStatus: Sendable, Equatable {
    public var isIndexing = false
    public var processed = 0
    public var total = 0
    public var currentFile = ""
    public var lastSummary: IndexSummary?
}

/// Owns the index, the configured folders and background indexing.
public actor IndexManager {
    public nonisolated let database: IndexDatabase
    public nonisolated let indexer: DocumentIndexer
    public nonisolated let searchEngine: SearchEngine
    public nonisolated let mergeManager: MergeManager

    public private(set) var status = IndexStatus()
    private var task: Task<IndexSummary, Never>?
    private var observers: [UUID: @Sendable (IndexStatus) -> Void] = [:]

    public init(database: IndexDatabase, registry: ParserRegistry = .shared, ocr: OCRProcessor? = nil) {
        self.database = database
        self.indexer = DocumentIndexer(database: database, registry: registry, ocr: ocr)
        self.searchEngine = SearchEngine(index: database)
        self.mergeManager = MergeManager(database: database)
    }

    public static func openDefault(ocr: OCRProcessor? = FallbackOCRProcessor.platformDefault()) throws -> IndexManager {
        IndexManager(database: try IndexDatabase(path: try FileUtils.defaultIndexURL().path), ocr: ocr)
    }

    public func observe(_ handler: @escaping @Sendable (IndexStatus) -> Void) -> UUID {
        let id = UUID()
        observers[id] = handler
        return id
    }

    public func removeObserver(_ id: UUID) { observers[id] = nil }

    public func folders() throws -> [String] { try database.folders() }

    public func addFolder(_ url: URL) throws { try database.addFolder(url.standardizedFileURL.path) }

    /// Stops watching a folder and drops its documents from the index.
    public func removeFolder(_ path: String) throws {
        try database.removeFolder(path)
        let prefix = path.hasSuffix("/") ? path : path + "/"
        for p in try database.filePaths(under: prefix) { try database.deleteDocument(path: p) }
    }

    /// Starts indexing all configured folders in the background (no-op if already running).
    @discardableResult
    public func startIndexing() -> Task<IndexSummary, Never> {
        if let task { return task }
        let folders = (try? database.folders()) ?? []
        status = IndexStatus(isIndexing: true)
        publish()
        let t = Task { [indexer, manager = self] () -> IndexSummary in
            var total = IndexSummary()
            for folder in folders {
                if Task.isCancelled { break }
                let s = await indexer.indexFolder(URL(fileURLWithPath: folder, isDirectory: true)) { p in
                    Task { await manager.update(p) }
                }
                total.indexed += s.indexed; total.unchanged += s.unchanged; total.failed += s.failed; total.removed += s.removed
            }
            await manager.finish(total)
            return total
        }
        task = t
        return t
    }

    public func cancelIndexing() { task?.cancel() }

    private func update(_ p: IndexProgress) {
        guard status.isIndexing else { return }
        status.processed = p.processed
        status.total = p.total
        status.currentFile = p.currentFile
        publish()
    }

    private func finish(_ summary: IndexSummary) {
        status.isIndexing = false
        status.lastSummary = summary
        task = nil
        publish()
    }

    private func publish() { for o in observers.values { o(status) } }
}
