import Foundation
import XCTest
@testable import DocFetcherCore

class TempDirTestCase: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("docfetcher-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    @discardableResult
    func write(_ name: String, _ text: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func zip(_ name: String, files: [String: String]) throws -> URL {
        let staging = dir.appendingPathComponent("stage-\(UUID().uuidString)")
        for (n, c) in files {
            let u = staging.appendingPathComponent(n)
            try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try c.write(to: u, atomically: true, encoding: .utf8)
        }
        let out = dir.appendingPathComponent(name)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.currentDirectoryURL = staging
        p.arguments = ["zip", "-q", "-r", out.path] + files.keys.sorted()
        try p.run(); p.waitUntilExit()
        try? FileManager.default.removeItem(at: staging)
        guard p.terminationStatus == 0 else { throw XCTSkip("zip tool unavailable") }
        return out
    }

    func makeIndex() throws -> IndexDatabase { try IndexDatabase.inMemory() }

    func doc(_ name: String, _ content: String, size: Int64 = 10, modified: Date = Date(), title: String? = nil) -> IndexableDocument {
        IndexableDocument(path: "/tmp/\(name)", filename: name, fileExtension: (name as NSString).pathExtension,
                          mimeType: "text/plain", size: size, modified: modified,
                          metadata: DocumentMetadata(title: title), content: content)
    }
}
