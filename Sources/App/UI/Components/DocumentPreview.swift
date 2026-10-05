import SwiftUI
import DocFetcherCore

/// Scrollable text preview with every query match highlighted.
struct DocumentPreview: View {
    let text: String
    let terms: [String]

    var body: some View {
        let ranges = Highlighter.ranges(of: terms, in: text)
        ScrollView {
            Text(ResultRow.attributed(String(text.prefix(200_000)), ranges: ranges.filter { NSMaxRange($0) <= 200_000 }))
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
    }
}
