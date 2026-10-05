import Foundation

public enum FileUtils {
    public static func appSupportDirectory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("DocFetcher", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static func defaultIndexURL() throws -> URL {
        try appSupportDirectory().appendingPathComponent("index.sqlite")
    }

    public static func fileSize(_ url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }

    public static func modificationDate(_ url: URL) -> Date {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.modificationDate] as? Date) ?? Date(timeIntervalSince1970: 0)
    }

    /// Recursively lists regular, non-hidden files below `root`.
    public static func enumerateFiles(in root: URL) -> [URL] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir) else { return [] }
        if !isDir.boolValue { return [root] }
        guard let en = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var result: [URL] = []
        for case let url as URL in en {
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                result.append(url)
            }
        }
        return result.sorted { $0.path < $1.path }
    }

    /// Runs an external tool, returning stdout. Output is capped to guard against decompression bombs.
    public static func runTool(_ arguments: [String], maxOutput: Int = 64 * 1024 * 1024) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch {
            throw ParserError.toolUnavailable(arguments.first ?? "tool")
        }
        var data = Data()
        let reader = pipe.fileHandleForReading
        while true {
            let chunk = reader.availableData
            if chunk.isEmpty { break }
            data.append(chunk)
            if data.count > maxOutput {
                process.terminate()
                try? reader.close()
                break
            }
        }
        process.waitUntilExit()
        if data.count > maxOutput { throw ParserError.corrupted("output too large") }
        if process.terminationStatus != 0 && data.isEmpty {
            throw ParserError.corrupted("\(arguments.first ?? "tool") failed (\(process.terminationStatus))")
        }
        return data
    }
}
