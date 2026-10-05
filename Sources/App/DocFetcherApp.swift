import SwiftUI
import DocFetcherCore

@main
struct DocFetcherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var search: SearchViewModel
    @StateObject private var indexing: IndexingViewModel
    @StateObject private var settings = SettingsViewModel()

    init() {
        let manager: IndexManager
        do {
            let ocrEnabled = UserDefaults.standard.object(forKey: "ocrEnabled") as? Bool ?? true
            manager = try IndexManager.openDefault(ocr: ocrEnabled ? FallbackOCRProcessor.platformDefault() : nil)
        } catch {
            // Fall back to a temporary in-memory index so the app still launches (nothing will be persisted).
            NSLog("DocFetcher: could not open index database: \(error)")
            manager = IndexManager(database: (try? IndexDatabase.inMemory())!)
        }
        _search = StateObject(wrappedValue: SearchViewModel(manager: manager))
        _indexing = StateObject(wrappedValue: IndexingViewModel(manager: manager))
    }

    var body: some Scene {
        WindowGroup("DocFetcher") {
            MainWindow()
                .environmentObject(search)
                .environmentObject(indexing)
                .environmentObject(settings)
                .frame(minWidth: 900, minHeight: 560)
                .task { await indexing.load(); indexing.startIndexing() }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Re-index All Folders") { indexing.startIndexing() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(indexing)
                .environmentObject(settings)
        }
    }
}
