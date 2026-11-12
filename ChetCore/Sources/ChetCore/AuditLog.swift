import Foundation

/// Append-only JSON Lines record of every clean action.
public struct AuditLog: Sendable {
    public static let maxBytes: Int64 = 8 * 1024 * 1024

    public let url: URL

    public var rotatedURL: URL {
        url.deletingLastPathComponent().appendingPathComponent("clean.1.log")
    }

    public init(
        url: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Logs/chet/clean.log")
    ) {
        self.url = url
    }

    struct Entry: Codable, Equatable {
        let time: String
        let path: String
        let bytes: Int64
        /// Optional so lines written before the field existed still decode.
        let category: String?
        let mode: String
        let result: String
        /// Optional so lines written before the field existed still decode.
        let reason: String?
    }

    public func append(
        _ item: ScanItem, _ outcome: CleanOutcome, dryRun: Bool, reason: RefusalReason? = nil,
        at date: Date = Date()
    ) {
        append(
            category: item.categoryID, path: item.url.path, bytes: item.reclaimableBytes, mode: item.mode,
            result: outcome.logValue, dryRun: dryRun, reason: reason, at: date)
    }

    /// One row for a non-scan action, such as an app uninstall row.
    public func append(
        category: String, path: String, bytes: Int64, mode: DeleteMode, result: String, dryRun: Bool,
        reason: RefusalReason? = nil, at date: Date = Date()
    ) {
        let entry = Entry(
            time: ISO8601DateFormatter().string(from: date), path: path, bytes: bytes, category: category,
            mode: mode.rawValue,
            // "dry-removed" can never be misread as a performed deletion.
            result: dryRun ? "dry-" + result : result,
            reason: reason?.rawValue)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard var line = try? encoder.encode(entry) else { return }
        line.append(0x0A)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        rotateIfNeeded()
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: url)
        }
    }

    private func rotateIfNeeded() {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        guard size >= Self.maxBytes else { return }
        try? FileManager.default.removeItem(at: rotatedURL)
        try? FileManager.default.moveItem(at: url, to: rotatedURL)
    }
}
