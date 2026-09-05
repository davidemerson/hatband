import Foundation
import os

/// The only logger. Messages are static strings, so nothing personal can
/// be interpolated; an error's description is logged private.
nonisolated enum Log {
    private static let logger = Logger(subsystem: "link.hatband.ios", category: "app")

    static func event(_ message: StaticString) {
        let text = message.description
        logger.info("\(text, privacy: .public)")
    }

    static func failure(_ message: StaticString, _ error: any Error) {
        let text = message.description
        let detail = String(describing: error)
        logger.error("\(text, privacy: .public): \(detail, privacy: .private)")
    }
}
