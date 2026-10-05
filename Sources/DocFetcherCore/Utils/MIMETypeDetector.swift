import Foundation

public enum MIMETypeDetector {
    private static let byExtension: [String: String] = [
        "txt": "text/plain", "md": "text/markdown", "csv": "text/csv", "log": "text/plain",
        "html": "text/html", "htm": "text/html", "xhtml": "application/xhtml+xml", "xml": "text/xml",
        "rtf": "application/rtf", "pdf": "application/pdf", "svg": "image/svg+xml",
        "doc": "application/msword",
        "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "xls": "application/vnd.ms-excel",
        "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "ppt": "application/vnd.ms-powerpoint",
        "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        "odt": "application/vnd.oasis.opendocument.text", "ods": "application/vnd.oasis.opendocument.spreadsheet",
        "odp": "application/vnd.oasis.opendocument.presentation", "odg": "application/vnd.oasis.opendocument.graphics",
        "epub": "application/epub+zip", "chm": "application/vnd.ms-htmlhelp",
        "mp3": "audio/mpeg", "flac": "audio/flac",
        "jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png", "tif": "image/tiff", "tiff": "image/tiff",
        "heic": "image/heic",
        "zip": "application/zip", "tar": "application/x-tar", "gz": "application/gzip", "tgz": "application/gzip",
    ]

    public static func mimeType(forExtension ext: String) -> String? { byExtension[ext.lowercased()] }

    /// Detects a MIME type from file content (magic bytes), falling back to the extension.
    public static func detect(url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if let handle = try? FileHandle(forReadingFrom: url) {
            defer { try? handle.close() }
            let head = handle.readData(ofLength: 16)
            if let sniffed = sniff(head) {
                // ZIP-based formats keep their extension-derived type.
                if sniffed == "application/zip", let byExt = byExtension[ext] { return byExt }
                return sniffed
            }
        }
        return byExtension[ext] ?? "application/octet-stream"
    }

    static func sniff(_ head: Data) -> String? {
        let b = [UInt8](head)
        func starts(_ s: [UInt8]) -> Bool { b.count >= s.count && Array(b[0..<s.count]) == s }
        if starts(Array("%PDF".utf8)) { return "application/pdf" }
        if starts([0x50, 0x4B, 0x03, 0x04]) { return "application/zip" }
        if starts([0xD0, 0xCF, 0x11, 0xE0]) { return "application/x-ole-storage" }
        if starts(Array("{\\rtf".utf8)) { return "application/rtf" }
        if starts([0x1F, 0x8B]) { return "application/gzip" }
        if starts(Array("fLaC".utf8)) { return "audio/flac" }
        if starts(Array("ID3".utf8)) { return "audio/mpeg" }
        if starts([0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if starts([0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if starts(Array("ITSF".utf8)) { return "application/vnd.ms-htmlhelp" }
        return nil
    }
}
