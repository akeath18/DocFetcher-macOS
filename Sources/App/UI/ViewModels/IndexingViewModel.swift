import Foundation
import DocFetcherCore

@MainActor
final class IndexingViewModel: ObservableObject {
    @Published private(set) var folders: [String] = []
    @Published private(set) var status = IndexStatus()
    @Published private(set) var errors: [(path: String, message: String)] = []
    @Published var errorMessage: String?

    let manager: IndexManager
    private var observerID: UUID?

    init(manager: IndexManager) { self.manager = manager }

    func load() async {
        observerID = await manager.observe { [weak self] status in
            Task { @MainActor in self?.status = status }
        }
        await refresh()
    }

    func refresh() async {
        folders = (try? await manager.folders()) ?? []
        errors = (try? manager.database.errors()) ?? []
    }

    func add(folder url: URL) {
        Task {
            do { try await manager.addFolder(url) } catch { errorMessage = "\(error)" }
            await refresh()
            startIndexing()
        }
    }

    func remove(folder path: String) {
        Task {
            do { try await manager.removeFolder(path) } catch { errorMessage = "\(error)" }
            await refresh()
        }
    }

    func startIndexing() {
        Task {
            let task = await manager.startIndexing()
            _ = await task.value
            await refresh()
        }
    }

    func cancel() { Task { await manager.cancelIndexing() } }

    var progressFraction: Double {
        status.total > 0 ? Double(status.processed) / Double(status.total) : 0
    }
}
