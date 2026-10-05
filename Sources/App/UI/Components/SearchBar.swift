import SwiftUI

struct SearchBar: View {
    @Binding var text: String
    var suggestions: [String]
    var onSubmit: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search documents…  (AND, OR, NOT, \"phrase\", title:, filename:, type:pdf)", text: $text)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(onSubmit)
                if !text.isEmpty {
                    Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
            if focused, !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(suggestions, id: \.self) { s in
                        Button { text = s } label: {
                            Text(s).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3).padding(.horizontal, 8)
                        }.buttonStyle(.plain)
                    }
                }
                .background(Color(nsColor: .windowBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            }
        }
    }
}
