import Foundation
import DocFetcherCore

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = "" { didSet { scheduleSearch() } }
    @Published var sort: SortOrder = .relevance { didSet { scheduleSearch(immediate: true) } }
    @Published var typeFilter: Set<String> = [] { didSet { scheduleSearch(immediate: true) } }
    @Published var modifiedAfter: Date? { didSet { scheduleSearch(immediate: true) } }
    @Published var modifiedBefore: Date? { didSet { scheduleSearch(immediate: true) } }
    @Published var fuzzy = false { didSet { scheduleSearch(immediate: true) } }
    @Published private(set) var results: [SearchResult] = []
    @Published private(set) var suggestions: [String] = []
    @Published private(set) var savedSearches: [SavedSearch] = []
    @Published private(set) var history: [SearchHistoryEntry] = []
    @Published var selection: Int64?
    @Published var errorMessage: String?

    let manager: IndexManager
    private var searchTask: Task<Void, Never>?

    init(manager: IndexManager) {
        self.manager = manager
        reloadStores()
    }

    var selectedResult: SearchResult? { results.first { $0.id == selection } }

    /// Extensions offered in the type filter.
    static let availableTypes = ["pdf", "docx", "doc", "xlsx", "xls", "pptx", "ppt", "odt", "ods", "odp", "rtf",
                                 "html", "txt", "md", "epub", "svg", "mp3", "flac", "zip"]

    func scheduleSearch(immediate: Bool = false) {
        searchTask?.cancel()
        let text = query
        let engine = manager.searchEngine
        let filters = SearchFilters(extensions: typeFilter, modifiedAfter: modifiedAfter, modifiedBefore: modifiedBefore)
        let options = SearchOptions(sort: sort, fuzzy: fuzzy)
        searchTask = Task { [weak self] in
            if !immediate { try? await Task.sleep(nanoseconds: 150_000_000) }
            if Task.isCancelled { return }
            let outcome = await Task.detached { () -> Result<([SearchResult], [String]), Error> in
                Result { (try engine.search(text, filters: filters, options: options), engine.suggestions(for: text)) }
            }.value
            guard let self, !Task.isCancelled else { return }
            switch outcome {
            case .success(let (r, s)):
                self.results = r
                self.suggestions = s
                self.errorMessage = nil
                if let sel = self.selection, !r.contains(where: { $0.id == sel }) { self.selection = nil }
            case .failure(let e):
                self.errorMessage = "\(e)"
            }
        }
    }

    /// Records the current query in history (called when the user submits the search field).
    func commit() {
        let engine = manager.searchEngine
        try? engine.store.addHistory(query: query, resultCount: results.count)
        reloadStores()
    }

    func saveCurrentSearch(named name: String) {
        guard !name.isEmpty, !query.isEmpty else { return }
        do { try manager.searchEngine.store.save(name: name, query: query) } catch { errorMessage = "\(error)" }
        reloadStores()
    }

    func deleteSavedSearch(_ s: SavedSearch) {
        try? manager.searchEngine.store.deleteSavedSearch(id: s.id)
        reloadStores()
    }

    func reloadStores() {
        savedSearches = (try? manager.searchEngine.store.savedSearches()) ?? []
        history = (try? manager.searchEngine.store.history(limit: 20)) ?? []
    }

    func export(to url: URL, format: ExportFormat) {
        do { try ResultExporter.write(results, format: format, to: url) } catch { errorMessage = "\(error)" }
    }

    func mergeSelected(_ ids: Set<Int64>, title: String) {
        do {
            _ = try manager.mergeManager.merge(documentIDs: Array(ids), title: title)
            scheduleSearch(immediate: true)
        } catch { errorMessage = "\(error)" }
    }

    func undoMerge(_ id: Int64) {
        do { try manager.mergeManager.undoMerge(mergedID: id); scheduleSearch(immediate: true) }
        catch { errorMessage = "\(error)" }
    }

    func setUseOCR(_ id: Int64, _ on: Bool) {
        try? manager.database.setUseOCR(id: id, on)
        scheduleSearch(immediate: true)
    }
}
