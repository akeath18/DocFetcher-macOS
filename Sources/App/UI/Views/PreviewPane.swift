import SwiftUI
import DocFetcherCore

struct PreviewPane: View {
    @EnvironmentObject var search: SearchViewModel

    var body: some View {
        if let result = search.selectedResult {
            let doc = result.document
            VStack(alignment: .leading, spacing: 8) {
                Text(doc.metadata.title ?? doc.filename).font(.title2).bold()
                HStack(spacing: 12) {
                    if let a = doc.metadata.author { Label(a, systemImage: "person") }
                    Label(doc.modified.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    Label(doc.mimeType, systemImage: "doc")
                }.font(.caption).foregroundStyle(.secondary)
                if let confidence = doc.ocrConfidence, let id = doc.id {
                    HStack {
                        Text(String(format: "OCR confidence %.0f%%", confidence * 100))
                        Toggle("Use OCR text", isOn: Binding(get: { doc.useOCR }, set: { search.setUseOCR(id, $0) }))
                    }.font(.caption)
                }
                Divider()
                DocumentPreview(text: doc.effectiveText, terms: SearchQuery(search.query).highlightTerms)
            }
            .padding()
        } else {
            Text("Select a result to preview").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
