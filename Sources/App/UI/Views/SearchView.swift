import SwiftUI
import DocFetcherCore

struct SearchView: View {
    @EnvironmentObject var search: SearchViewModel
    @EnvironmentObject var settings: SettingsViewModel
    @State private var saveName = ""
    @State private var showSave = false

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                SearchBar(text: $search.query, suggestions: search.suggestions, onSubmit: search.commit)
                Button { showSave = true } label: { Image(systemName: "bookmark") }
                    .help("Save this search").disabled(search.query.isEmpty)
            }
            HStack {
                Menu(search.typeFilter.isEmpty ? "All types" : search.typeFilter.sorted().joined(separator: ", ")) {
                    Button("All types") { search.typeFilter = [] }
                    Divider()
                    ForEach(SearchViewModel.availableTypes, id: \.self) { t in
                        Toggle(t, isOn: Binding(
                            get: { search.typeFilter.contains(t) },
                            set: { on in if on { search.typeFilter.insert(t) } else { search.typeFilter.remove(t) } }))
                    }
                }.frame(maxWidth: 220)
                DatePicker("After", selection: Binding(get: { search.modifiedAfter ?? Date() },
                                                       set: { search.modifiedAfter = $0 }), displayedComponents: .date)
                    .labelsHidden()
                    .opacity(search.modifiedAfter == nil ? 0.5 : 1)
                DatePicker("Before", selection: Binding(get: { search.modifiedBefore ?? Date() },
                                                        set: { search.modifiedBefore = $0 }), displayedComponents: .date)
                    .labelsHidden()
                    .opacity(search.modifiedBefore == nil ? 0.5 : 1)
                if search.modifiedAfter != nil || search.modifiedBefore != nil {
                    Button("Clear dates") { search.modifiedAfter = nil; search.modifiedBefore = nil }
                }
                Spacer()
                Toggle("Fuzzy", isOn: $search.fuzzy).toggleStyle(.checkbox)
            }
            if let e = search.errorMessage { Text(e).foregroundStyle(.red).font(.caption) }
            ResultsView()
        }
        .padding(8)
        .onAppear { search.fuzzy = settings.fuzzySearch; search.scheduleSearch(immediate: true) }
        .alert("Save Search", isPresented: $showSave) {
            TextField("Name", text: $saveName)
            Button("Save") { search.saveCurrentSearch(named: saveName); saveName = "" }
            Button("Cancel", role: .cancel) {}
        }
    }
}
