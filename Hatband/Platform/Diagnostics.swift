import Foundation
import MetricKit

/// MetricKit crash and hang reports, kept as JSON files under
/// Application Support/Diagnostics for the user to read, share or delete.
/// Nothing is sent anywhere by the app.
@MainActor enum Diagnostics {
    private static var subscriber: DiagnosticsSubscriber?

    /// Application Support/Diagnostics.
    nonisolated static var directoryURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Diagnostics", isDirectory: true)
    }

    /// Registers once, and stores whatever MetricKit already holds.
    static func subscribe() {
        guard subscriber == nil else { return }
        let subscriber = DiagnosticsSubscriber()
        self.subscriber = subscriber
        MXMetricManager.shared.add(subscriber)
        store(MXMetricManager.shared.pastDiagnosticPayloads)
    }

    /// Every stored report, oldest first: names begin with the time.
    nonisolated static func files() -> [URL] {
        let contents = try? FileManager.default.contentsOfDirectory(
            at: directoryURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        return (contents ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    nonisolated static func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    nonisolated static func removeAll() {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    /// Writes each payload's `jsonRepresentation()` as its own file.
    nonisolated static func store(_ payloads: [MXDiagnosticPayload]) {
        guard !payloads.isEmpty else { return }
        do {
            try FileManager.default.createDirectory(
                at: directoryURL, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete])
            for payload in payloads {
                let url = directoryURL.appendingPathComponent(fileName(for: payload.timeStampEnd))
                try payload.jsonRepresentation().write(to: url, options: [.atomic, .completeFileProtection])
            }
            Log.event("diagnostics stored")
        } catch {
            Log.failure("diagnostics", error)
        }
    }

    /// `diagnostic-<UTC time>-<random>.json`: sorts by time, never collides.
    nonisolated static func fileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let suffix = String(UInt32.random(in: 0...0xFFFF), radix: 16)
        return "diagnostic-" + formatter.string(from: date) + "-" + suffix + ".json"
    }
}

/// Called by MetricKit on its own queue; touches no main-actor state.
@MainActor final class DiagnosticsSubscriber: NSObject, MXMetricManagerSubscriber {
    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
    }

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        Diagnostics.store(payloads)
    }
}
