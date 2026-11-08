import Foundation

/// Append-only JSON Lines record of every clean action.
public struct AuditLog: Sendable {
    public let url: URL

    public init(
        url: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Logs/Mackit/clean.log")
    ) {
        self.url = url
    }

    struct Entry: Codable, Equatable {
        let time: String
        let path: String
        let bytes: Int64
        let mode: String
        let result: String
    }

    public func append(
        _ item: ScanItem, _ outcome: CleanOutcome, dryRun: Bool, at date: Date = Date()
    ) {
        append(
            path: item.url.path, bytes: item.reclaimableBytes, mode: item.mode, result: outcome.logValue,
            dryRun: dryRun, at: date)
    }

    /// One row for a non-scan action, such as an app uninstall row.
    public func append(
        path: String, bytes: Int64, mode: DeleteMode, result: String, dryRun: Bool, at date: Date = Date()
    ) {
        let entry = Entry(
            time: ISO8601DateFormatter().string(from: date), path: path, bytes: bytes, mode: mode.rawValue,
            // "dry-removed" can never be misread as a performed deletion.
            result: dryRun ? "dry-" + result : result)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard var line = try? encoder.encode(entry) else { return }
        line.append(0x0A)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: url)
        }
    }
}
