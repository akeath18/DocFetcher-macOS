import SwiftUI
import DocFetcherCore

struct MainWindow: View {
    @EnvironmentObject var search: SearchViewModel
    @EnvironmentObject var indexing: IndexingViewModel

    var body: some View {
        NavigationSplitView {
            List {
                Section("Saved Searches") {
                    ForEach(search.savedSearches) { s in
                        Button(s.name) { search.query = s.query }
                            .contextMenu { Button("Delete") { search.deleteSavedSearch(s) } }
                    }
                }
                Section("Recent") {
                    ForEach(Array(search.history.enumerated()), id: \.offset) { _, h in
                        Button(h.query) { search.query = h.query }.lineLimit(1)
                    }
                }
                Section("Indexed Folders") {
                    ForEach(indexing.folders, id: \.self) { f in
                        Text((f as NSString).lastPathComponent).help(f)
                    }
                    Button("Add Folder…") { chooseFolder() }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            HSplitView {
                SearchView().frame(minWidth: 420)
                PreviewPane().frame(minWidth: 300)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if indexing.status.isIndexing {
                HStack {
                    ProgressView(value: indexing.progressFraction).frame(width: 160)
                    Text("Indexing \(indexing.status.currentFile)").lineLimit(1).font(.caption)
                    Spacer()
                    Button("Cancel") { indexing.cancel() }
                }.padding(6).background(.bar)
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { panel.urls.forEach(indexing.add(folder:)) }
    }
}
