import Foundation
import OSLog

/// Debug logging. View with:
/// `log stream --level debug --predicate 'subsystem == "dev.desknet.app"'`
/// ponytail: no in-app debug log buffer like the SDK's `debugLogs()`; add one if a UI needs it.
enum DesknetDiagnostics {
    private static let logger = Logger(subsystem: "dev.desknet.app", category: "Debug")

    static func log(_ category: String, _ message: String) {
        logger.debug("[\(category, privacy: .public)] \(message, privacy: .public)")
    }
}
