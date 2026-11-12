import Foundation

public struct ScanSnapshot: Codable, Sendable, Equatable {
    public struct Category: Codable, Sendable, Equatable {
        public let id: String
        public let title: String
        public let items: [ScanItem]

        public init(id: String, title: String, items: [ScanItem]) {
            self.id = id
            self.title = title
            self.items = items
        }
    }

    public struct Group: Codable, Sendable, Equatable {
        public let keeper: URL
        public let itemURLs: [URL]

        public init(keeper: URL, itemURLs: [URL]) {
            self.keeper = keeper
            self.itemURLs = itemURLs
        }
    }

    public static let currentVersion = 1

    public let version: Int
    public let date: Date
    public let scopeSummary: String
    public let categories: [Category]
    public let groups: [String: [Group]]
    public let coverage: CoverageReport?

    public init(
        version: Int = ScanSnapshot.currentVersion, date: Date, scopeSummary: String,
        categories: [Category], groups: [String: [Group]], coverage: CoverageReport?
    ) {
        self.version = version
        self.date = date
        self.scopeSummary = scopeSummary
        self.categories = categories
        self.groups = groups
        self.coverage = coverage
    }
}

public struct ScanSnapshotStore: Sendable {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Chet/scan-snapshot.json")
    }

    public let url: URL

    public init(url: URL = ScanSnapshotStore.defaultURL) {
        self.url = url
    }

    public func load() -> ScanSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(ScanSnapshot.self, from: data),
            snapshot.version == ScanSnapshot.currentVersion
        else {
            quarantine(data)
            return nil
        }
        return snapshot
    }

    public func save(_ snapshot: ScanSnapshot) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            let backup = url.appendingPathExtension("bak")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: url, to: backup)
        }
        try? data.write(to: url, options: .atomic)
    }

    private func quarantine(_ data: Data) {
        let corrupt = url.appendingPathExtension("corrupt")
        try? FileManager.default.removeItem(at: corrupt)
        try? data.write(to: corrupt)
    }
}
