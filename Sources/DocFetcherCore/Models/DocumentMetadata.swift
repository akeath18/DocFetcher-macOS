import Foundation

public struct DocumentMetadata: Codable, Equatable, Sendable {
    public var title: String?
    public var author: String?
    public var created: Date?
    public var modified: Date?
    public var pageCount: Int?
    public var extra: [String: String]

    public init(title: String? = nil, author: String? = nil, created: Date? = nil, modified: Date? = nil,
                pageCount: Int? = nil, extra: [String: String] = [:]) {
        self.title = title
        self.author = author
        self.created = created
        self.modified = modified
        self.pageCount = pageCount
        self.extra = extra
    }
}

public enum DocumentKind: String, Codable, Sendable {
    case file
    case merged
}
