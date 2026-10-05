import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var indexing: IndexingViewModel
    @EnvironmentObject var settings: SettingsViewModel

    var body: some View {
        TabView {
            Form {
                Toggle("Fuzzy matching (typo tolerance)", isOn: $settings.fuzzySearch)
                Toggle("OCR scanned PDFs and images", isOn: $settings.ocrEnabled)
                Stepper("Max results: \(settings.maxResults)", value: $settings.maxResults, in: 50...1000, step: 50)
            }
            .padding().tabItem { Label("General", systemImage: "gear") }

            VStack(alignment: .leading) {
                List {
                    ForEach(indexing.folders, id: \.self) { f in
                        HStack {
                            Text(f)
                            Spacer()
                            Button("Remove") { indexing.remove(folder: f) }
                        }
                    }
                }
                HStack {
                    Button("Add Folder…") {
                        let p = NSOpenPanel()
                        p.canChooseDirectories = true
                        p.canChooseFiles = false
                        if p.runModal() == .OK, let url = p.url { indexing.add(folder: url) }
                    }
                    Button("Re-index Now") { indexing.startIndexing() }
                }
                if !indexing.errors.isEmpty {
                    Text("\(indexing.errors.count) files could not be indexed").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding().tabItem { Label("Folders", systemImage: "folder") }
        }
        .frame(width: 520, height: 320)
    }
}
