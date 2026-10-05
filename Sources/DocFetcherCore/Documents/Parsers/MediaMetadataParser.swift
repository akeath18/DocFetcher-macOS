import Foundation
#if canImport(ImageIO)
import ImageIO
#endif

/// Extracts searchable metadata (tags) from MP3 (ID3v2) and FLAC (Vorbis comments) files.
public struct MediaMetadataParser: DocumentParser {
    public let name = "Audio metadata"
    public let supportedExtensions: Set<String> = ["mp3", "flac"]
    public init() {}

    public func parse(url: URL) throws -> ParsedDocument {
        guard let handle = try? FileHandle(forReadingFrom: url) else { throw ParserError.unreadable(url.lastPathComponent) }
        defer { try? handle.close() }
        let head = handle.readData(ofLength: 4 * 1024 * 1024)
        let tags: [String: String]
        switch url.pathExtension.lowercased() {
        case "mp3": tags = Self.id3Tags([UInt8](head))
        default: tags = Self.flacTags([UInt8](head))
        }
        guard !tags.isEmpty else { throw ParserError.corrupted("no tags found") }
        let order = ["title", "artist", "album", "genre", "year", "comment", "lyrics"]
        let text = order.compactMap { k in tags[k].map { "\(k): \($0)" } }.joined(separator: "\n")
        return ParsedDocument(text: text, metadata: DocumentMetadata(title: tags["title"], author: tags["artist"], extra: tags))
    }

    static func id3Tags(_ b: [UInt8]) -> [String: String] {
        guard b.count > 10, b[0] == 0x49, b[1] == 0x44, b[2] == 0x33 else { return [:] }
        let major = b[3]
        guard major >= 3 else { return [:] }
        let size = Int(b[6] & 0x7F) << 21 | Int(b[7] & 0x7F) << 14 | Int(b[8] & 0x7F) << 7 | Int(b[9] & 0x7F)
        let end = min(10 + size, b.count)
        let names = ["TIT2": "title", "TPE1": "artist", "TALB": "album", "TCON": "genre", "TYER": "year", "TDRC": "year"]
        var tags: [String: String] = [:]
        var pos = 10
        while pos + 10 <= end {
            let id = String(decoding: b[pos..<pos + 4], as: UTF8.self)
            if b[pos] == 0 { break }
            let fsize: Int
            if major == 4 {
                fsize = Int(b[pos + 4] & 0x7F) << 21 | Int(b[pos + 5] & 0x7F) << 14 | Int(b[pos + 6] & 0x7F) << 7 | Int(b[pos + 7] & 0x7F)
            } else {
                fsize = Int(b[pos + 4]) << 24 | Int(b[pos + 5]) << 16 | Int(b[pos + 6]) << 8 | Int(b[pos + 7])
            }
            let start = pos + 10
            guard fsize > 1, start + fsize <= end else { break }
            if let key = names[id] {
                let enc = b[start]
                let body = Array(b[(start + 1)..<(start + fsize)])
                let value: String?
                switch enc {
                case 0: value = String(data: Data(body), encoding: .isoLatin1)
                case 1: value = String(data: Data(body), encoding: .utf16)
                case 2: value = String(data: Data(body), encoding: .utf16BigEndian)
                default: value = String(data: Data(body), encoding: .utf8)
                }
                if let v = value?.trimmingCharacters(in: CharacterSet(charactersIn: "\0").union(.whitespacesAndNewlines)), !v.isEmpty {
                    tags[key] = v
                }
            }
            pos = start + fsize
        }
        return tags
    }

    static func flacTags(_ b: [UInt8]) -> [String: String] {
        guard b.count > 8, b[0] == 0x66, b[1] == 0x4C, b[2] == 0x61, b[3] == 0x43 else { return [:] }
        var pos = 4
        while pos + 4 <= b.count {
            let header = b[pos]
            let isLast = header & 0x80 != 0
            let type = header & 0x7F
            let len = Int(b[pos + 1]) << 16 | Int(b[pos + 2]) << 8 | Int(b[pos + 3])
            let start = pos + 4
            guard start + len <= b.count else { break }
            if type == 4 {
                func le32(_ o: Int) -> Int? {
                    guard o + 4 <= start + len else { return nil }
                    return Int(b[o]) | Int(b[o + 1]) << 8 | Int(b[o + 2]) << 16 | Int(b[o + 3]) << 24
                }
                var o = start
                guard let vendor = le32(o) else { break }
                o += 4 + vendor
                guard let count = le32(o) else { break }
                o += 4
                var tags: [String: String] = [:]
                for _ in 0..<min(count, 1000) {
                    guard let l = le32(o), o + 4 + l <= start + len else { break }
                    let comment = String(decoding: b[(o + 4)..<(o + 4 + l)], as: UTF8.self)
                    if let eq = comment.firstIndex(of: "=") {
                        let key = comment[comment.startIndex..<eq].lowercased()
                        let mapped = key == "date" ? "year" : key
                        tags[mapped] = String(comment[comment.index(after: eq)...])
                    }
                    o += 4 + l
                }
                return tags
            }
            if isLast { break }
            pos = start + len
        }
        return [:]
    }
}

/// Images: EXIF/TIFF/IPTC metadata via ImageIO. Text comes from OCR when available.
public struct ImageParser: DocumentParser {
    public let name = "Image"
    public let supportedExtensions: Set<String> = ["jpg", "jpeg", "png", "tif", "tiff", "heic"]
    public init() {}

    public func parse(url: URL) throws -> ParsedDocument {
        var extra: [String: String] = [:]
        var metadata = DocumentMetadata()
        #if canImport(ImageIO)
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else {
            throw ParserError.corrupted("cannot read image \(url.lastPathComponent)")
        }
        if let w = props[kCGImagePropertyPixelWidth], let h = props[kCGImagePropertyPixelHeight] { extra["dimensions"] = "\(w)x\(h)" }
        if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            if let make = tiff[kCGImagePropertyTIFFMake] as? String { extra["camera make"] = make }
            if let model = tiff[kCGImagePropertyTIFFModel] as? String { extra["camera model"] = model }
            metadata.author = tiff[kCGImagePropertyTIFFArtist] as? String
            if let desc = tiff[kCGImagePropertyTIFFImageDescription] as? String { metadata.title = desc }
        }
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let dateString = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy:MM:dd HH:mm:ss"
            metadata.created = f.date(from: dateString)
        }
        #endif
        metadata.extra = extra
        let text = extra.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
        return ParsedDocument(text: text, metadata: metadata, needsOCR: true)
    }
}
