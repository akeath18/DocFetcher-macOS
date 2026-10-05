import Foundation

/// Searches inside ZIP, TAR and GZIP archives by parsing each supported entry.
public struct ArchiveParser: DocumentParser {
    public let name = "Archive"
    public let supportedExtensions: Set<String> = ["zip", "tar", "gz", "tgz"]
    private let registry: ParserRegistry
    static let maxEntries = 500
    static let maxEntrySize = 32 * 1024 * 1024

    init(registry: ParserRegistry) { self.registry = registry }

    private enum Kind { case zip, tar, tarGz, gz }

    private func kind(of url: URL) -> Kind {
        let n = url.lastPathComponent.lowercased()
        if n.hasSuffix(".tar.gz") || n.hasSuffix(".tgz") { return .tarGz }
        switch url.pathExtension.lowercased() {
        case "zip": return .zip
        case "tar": return .tar
        default: return .gz
        }
    }

    public func parse(url: URL) throws -> ParsedDocument {
        let kind = kind(of: url)
        var sections: [String] = []

        func ingest(name: String, data: () throws -> Data) {
            let entryURL = URL(fileURLWithPath: name)
            guard registry.canParse(entryURL), !(registry.parser(for: entryURL) is ArchiveParser) else { return }
            guard let bytes = try? data(), bytes.count <= Self.maxEntrySize else { return }
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + "." + entryURL.pathExtension)
            defer { try? FileManager.default.removeItem(at: tmp) }
            guard (try? bytes.write(to: tmp)) != nil, let parsed = try? registry.parse(url: tmp) else { return }
            sections.append("== \(name) ==\n\(parsed.text)")
        }

        switch kind {
        case .zip:
            let zip = ZipArchive(url: url)
            guard let entries = try? zip.entries() else { throw ParserError.corrupted("invalid ZIP archive") }
            for e in entries.prefix(Self.maxEntries) where !e.hasSuffix("/") { ingest(name: e) { try zip.read(e, maxSize: Self.maxEntrySize) } }
        case .tar, .tarGz:
            let flag = kind == .tarGz ? "-tzf" : "-tf"
            guard let listing = try? FileUtils.runTool(["tar", flag, url.path]) else { throw ParserError.corrupted("invalid TAR archive") }
            let names = String(decoding: listing, as: UTF8.self).split(separator: "\n").map(String.init)
            for e in names.prefix(Self.maxEntries) where !e.hasSuffix("/") {
                ingest(name: e) { try FileUtils.runTool(["tar", kind == .tarGz ? "-xzOf" : "-xOf", url.path, e], maxOutput: Self.maxEntrySize) }
            }
        case .gz:
            let inner = url.deletingPathExtension().lastPathComponent
            ingest(name: inner) { try FileUtils.runTool(["gzip", "-dc", url.path], maxOutput: Self.maxEntrySize) }
        }
        guard !sections.isEmpty else { throw ParserError.unsupported("archive contains no searchable files") }
        return ParsedDocument(text: sections.joined(separator: "\n\n"))
    }
}
