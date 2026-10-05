import Foundation
#if canImport(os)
import os
#endif

public enum Log {
    #if canImport(os)
    private static let logger = Logger(subsystem: "com.docfetcher.macos", category: "core")
    #endif

    public static func info(_ message: String) {
        #if canImport(os)
        logger.info("\(message, privacy: .public)")
        #endif
    }

    public static func error(_ message: String) {
        #if canImport(os)
        logger.error("\(message, privacy: .public)")
        #else
        FileHandle.standardError.write(Data((message + "\n").utf8))
        #endif
    }
}
