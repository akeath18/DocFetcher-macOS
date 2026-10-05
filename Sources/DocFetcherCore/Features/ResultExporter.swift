import Foundation

public enum ExportFormat: String, CaseIterable, Sendable {
    case csv, json, pdf
}

/// Exports search results to CSV, JSON or a simple text PDF.
public enum ResultExporter {
    public static func export(_ results: [SearchResult], format: ExportFormat) throws -> Data {
        switch format {
        case .csv: return Data(csv(results).utf8)
        case .json: return try json(results)
        case .pdf: return pdf(results)
        }
    }

    public static func write(_ results: [SearchResult], format: ExportFormat, to url: URL) throws {
        try export(results, format: format).write(to: url, options: .atomic)
    }

    static func csv(_ results: [SearchResult]) -> String {
        func field(_ s: String) -> String {
            // Neutralise spreadsheet formula injection.
            var v = s
            if let f = v.first, "=+-@".contains(f) { v = "'" + v }
            return "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let iso = ISO8601DateFormatter()
        var lines = ["filename,path,type,size,modified,score,title,author,snippet"]
        for r in results {
            let d = r.document
            lines.append([field(d.filename), field(d.path), field(d.fileExtension), String(d.size),
                          field(iso.string(from: d.modified)), String(format: "%.4f", r.score),
                          field(d.metadata.title ?? ""), field(d.metadata.author ?? ""), field(r.snippet)].joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    static func json(_ results: [SearchResult]) throws -> Data {
        struct Item: Encodable {
            let filename, path, type: String
            let size: Int64
            let modified: Date
            let score: Double
            let title, author: String?
            let snippet: String
        }
        let items = results.map { r in
            Item(filename: r.document.filename, path: r.document.path, type: r.document.fileExtension,
                 size: r.document.size, modified: r.document.modified, score: r.score,
                 title: r.document.metadata.title, author: r.document.metadata.author, snippet: r.snippet)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(items)
    }

    /// Minimal multi-page PDF (Helvetica text) with no external dependencies.
    static func pdf(_ results: [SearchResult]) -> Data {
        var lines: [String] = ["DocFetcher search results (\(results.count))", ""]
        for r in results {
            lines.append(r.document.filename)
            lines.append("  " + r.document.path)
            if !r.snippet.isEmpty { lines.append("  " + r.snippet) }
            lines.append("")
        }
        // Wrap to ~95 characters and paginate at 52 lines.
        var wrapped: [String] = []
        for l in lines {
            var rest = Substring(l)
            repeat {
                wrapped.append(String(rest.prefix(95)))
                rest = rest.dropFirst(95)
            } while !rest.isEmpty
        }
        let perPage = 52
        let pages = stride(from: 0, to: max(wrapped.count, 1), by: perPage).map { Array(wrapped[$0..<min($0 + perPage, wrapped.count)]) }

        func escape(_ s: String) -> String {
            // Standard fonts are Latin-1 only; replace anything else.
            var out = ""
            for u in s.unicodeScalars {
                switch u {
                case "(", ")", "\\": out += "\\" + String(u)
                case _ where u.value < 32 || u.value > 126: out += "?"
                default: out.unicodeScalars.append(u)
                }
            }
            return out
        }

        var objects: [String] = []
        let pageObjectStart = 4
        objects.append("<< /Type /Catalog /Pages 2 0 R >>")
        let kids = (0..<pages.count).map { "\(pageObjectStart + $0 * 2) 0 R" }.joined(separator: " ")
        objects.append("<< /Type /Pages /Kids [\(kids)] /Count \(pages.count) >>")
        objects.append("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")
        for (i, page) in pages.enumerated() {
            let contentID = pageObjectStart + i * 2 + 1
            objects.append("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 3 0 R >> >> /Contents \(contentID) 0 R >>")
            var stream = "BT /F1 9 Tf 12 TL 40 760 Td\n"
            for l in page { stream += "(\(escape(l))) Tj T*\n" }
            stream += "ET"
            objects.append("<< /Length \(stream.utf8.count) >>\nstream\n\(stream)\nendstream")
        }

        var out = Data("%PDF-1.4\n".utf8)
        var offsets: [Int] = []
        for (i, body) in objects.enumerated() {
            offsets.append(out.count)
            out.append(Data("\(i + 1) 0 obj\n\(body)\nendobj\n".utf8))
        }
        let xref = out.count
        var trailer = "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for o in offsets { trailer += String(format: "%010d 00000 n \n", o) }
        trailer += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        out.append(Data(trailer.utf8))
        return out
    }
}
