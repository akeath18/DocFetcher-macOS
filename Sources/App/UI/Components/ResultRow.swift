import SwiftUI
import DocFetcherCore

struct ResultRow: View {
    let result: SearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Image(systemName: result.document.kind == .merged ? "square.stack.3d.up" : "doc.text")
                Text(result.document.metadata.title ?? result.document.filename).font(.headline).lineLimit(1)
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: result.document.size, countStyle: .file))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !result.snippet.isEmpty {
                Text(Self.attributed(result.snippet, ranges: result.snippetHighlights)).font(.callout).lineLimit(3)
            }
            Text(result.document.path).font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
        }
        .padding(.vertical, 3)
    }

    static func attributed(_ text: String, ranges: [NSRange]) -> AttributedString {
        let ns = NSMutableAttributedString(string: text)
        for r in ranges where NSMaxRange(r) <= ns.length {
            ns.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.4), range: r)
            ns.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize), range: r)
        }
        return (try? AttributedString(ns, including: \.appKit)) ?? AttributedString(text)
    }
}
