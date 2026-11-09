import Foundation
#if canImport(os)
import os
#endif

/// The music's main steps in the system log, under subsystem "LofiScore", so a problem on
/// the phone can be traced in Console.app without a debugger. Only state changes: the
/// library loading, each book's text, mood changes and errors, a few lines an hour.
enum HostLog {
    #if canImport(os)
    private static let logger = Logger(subsystem: "LofiScore", category: "music")
    #endif

    static func note(_ message: String) {
        #if canImport(os)
        logger.notice("\(message, privacy: .public)")
        #endif
    }

    static func error(_ message: String) {
        #if canImport(os)
        logger.error("\(message, privacy: .public)")
        #endif
    }
}
