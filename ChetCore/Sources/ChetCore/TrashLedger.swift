import Foundation

public struct TrashOperation: Codable, Sendable, Equatable, Identifiable {
    public struct Entry: Codable, Sendable, Equatable {
        public let originalPath: String
        public let trashedPath: String
        public let bytes: Int64
        public let categoryID: String

        public init(originalPath: String, trashedPath: String, bytes: Int64, categoryID: String) {
            self.originalPath = originalPath
            self.trashedPath = trashedPath
            self.bytes = bytes
            self.categoryID = categoryID
        }
    }

    public let id: UUID
    public let date: Date
    public let entries: [Entry]

    public init(id: UUID = UUID(), date: Date = Date(), entries: [Entry]) {
        self.id = id
        self.date = date
        self.entries = entries
    }
}

public enum RestoreRefusal: String, Sendable, Equatable {
    case trashedItemMissing
    case originalPathOccupied
    case parentMissing
    case outsideHome
    case nameMismatch
}

public struct RestoreReport: Sendable, Equatable {
    public struct Unavailable: Sendable, Equatable {
        public let entry: TrashOperation.Entry
        public let reason: RestoreRefusal

        public init(entry: TrashOperation.Entry, reason: RestoreRefusal) {
            self.entry = entry
            self.reason = reason
        }
    }

    public var restored = 0
    public var unavailable: [Unavailable] = []

    public init() {}
}

/// Append-only JSON Lines record of every Trash-mode removal, one operation per line.
public struct TrashLedger: Sendable {
    public static let keptOperations = 10

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Chet/trash-ledger.jsonl")
    }

    public let url: URL
    public let home: URL

    public init(
        url: URL = TrashLedger.defaultURL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.url = url
        self.home = home
    }

    public func append(_ operation: TrashOperation) {
        guard let line = Self.encode(operation) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: url)
        }
        prune()
    }

    public func operations(limit: Int = keptOperations) -> [TrashOperation] {
        Array(allOperations().suffix(limit).reversed())
    }

    public func operation(id: UUID) -> TrashOperation? {
        allOperations().first { $0.id == id }
    }

    public func restore(_ operation: TrashOperation) -> RestoreReport {
        var report = RestoreReport()
        let homePath = Self.resolvedPath(home)
        for entry in operation.entries {
            let trashed = URL(fileURLWithPath: entry.trashedPath)
            let original = URL(fileURLWithPath: entry.originalPath)
            let originalPath = Self.resolvedPath(original)
            guard FileManager.default.fileExists(atPath: trashed.path) else {
                report.unavailable.append(.init(entry: entry, reason: .trashedItemMissing))
                continue
            }
            guard !FileManager.default.fileExists(atPath: originalPath) else {
                report.unavailable.append(.init(entry: entry, reason: .originalPathOccupied))
                continue
            }
            guard FileManager.default.fileExists(atPath: original.deletingLastPathComponent().path) else {
                report.unavailable.append(.init(entry: entry, reason: .parentMissing))
                continue
            }
            guard originalPath.hasPrefix(homePath + "/") else {
                report.unavailable.append(.init(entry: entry, reason: .outsideHome))
                continue
            }
            guard trashed.lastPathComponent == original.lastPathComponent else {
                report.unavailable.append(.init(entry: entry, reason: .nameMismatch))
                continue
            }
            do {
                try FileManager.default.moveItem(at: trashed, to: original)
                report.restored += 1
            } catch {
                report.unavailable.append(.init(entry: entry, reason: .trashedItemMissing))
            }
        }
        VerboseLog.event(
            .info, .storage, .storageRestore,
            .count(.restored, report.restored),
            .count(.unavailable, report.unavailable.count))
        VerboseLog.flush()
        return report
    }

    private func allOperations() -> [TrashOperation] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return data.split(separator: 0x0A).compactMap { line in
            try? decoder.decode(TrashOperation.self, from: Data(line))
        }
    }

    private func prune() {
        let all = allOperations()
        guard all.count > Self.keptOperations else { return }
        var data = Data()
        for operation in all.suffix(Self.keptOperations) {
            guard let line = Self.encode(operation) else { continue }
            data.append(line)
        }
        try? data.write(to: url)
    }

    private static func encode(_ operation: TrashOperation) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard var line = try? encoder.encode(operation) else { return nil }
        line.append(0x0A)
        return line
    }

    private static func resolvedPath(_ url: URL) -> String {
        let standard = url.standardizedFileURL
        return standard.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(standard.lastPathComponent).path
    }
}
