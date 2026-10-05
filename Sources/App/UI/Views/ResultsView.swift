import SwiftUI
import DocFetcherCore

struct ResultsView: View {
    @EnvironmentObject var search: SearchViewModel
    @State private var mergeSelection: Set<Int64> = []
    @State private var showMerge = false
    @State private var mergeTitle = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Sort", selection: $search.sort) {
                    Text("Relevance").tag(SortOrder.relevance)
                    Text("File Name").tag(SortOrder.filename)
                    Text("Date Modified").tag(SortOrder.dateModified)
                    Text("File Size").tag(SortOrder.fileSize)
                }.frame(width: 220)
                Spacer()
                Text("\(search.results.count) results").foregroundStyle(.secondary)
                Menu("Export") {
                    ForEach(ExportFormat.allCases, id: \.self) { f in
                        Button(f.rawValue.uppercased()) { export(f) }
                    }
                }.disabled(search.results.isEmpty)
            }
            .padding(8)
            Divider()
            List(selection: $mergeSelection) {
                ForEach(search.results) { r in
                    ResultRow(result: r).tag(r.id)
                        .contextMenu {
                            Button("Open") { open(r) }
                            Button("Reveal in Finder") { reveal(r) }
                            if mergeSelection.count >= 2 { Button("Merge Selected…") { showMerge = true } }
                            if r.document.kind == .merged, let id = r.document.id {
                                Button("Undo Merge") { search.undoMerge(id) }
                            }
                        }
                        .onTapGesture(count: 2) { open(r) }
                }
            }
            .overlay { if search.results.isEmpty { Text("No results").foregroundStyle(.secondary) } }
            .onChange(of: mergeSelection) { sel in search.selection = sel.count == 1 ? sel.first : nil }
        }
        .alert("Merge Documents", isPresented: $showMerge) {
            TextField("Title", text: $mergeTitle)
            Button("Merge") { search.mergeSelected(mergeSelection, title: mergeTitle.isEmpty ? "Merged document" : mergeTitle) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func open(_ r: SearchResult) {
        guard r.document.kind == .file else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: r.document.path))
    }

    private func reveal(_ r: SearchResult) {
        guard r.document.kind == .file else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: r.document.path)])
    }

    private func export(_ format: ExportFormat) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "results.\(format.rawValue)"
        if panel.runModal() == .OK, let url = panel.url { search.export(to: url, format: format) }
    }
}
