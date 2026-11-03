import Foundation

/// Library entries named after a bundle ID whose app (or any app from the same vendor) is not installed.
public struct LeftoverScanner: Sendable {
    public let home: URL
    public let policy: SafetyPolicy
    public let installedBundleIDs: Set<String>

    static let folders = [
        "Library/Application Support", "Library/Preferences", "Library/Containers", "Library/Group Containers",
        "Library/Saved Application State",
    ]

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        installedBundleIDs: Set<String> = LeftoverScanner.installedBundleIDs()
    ) {
        self.home = home
        self.policy = SafetyPolicy(home: home)
        self.installedBundleIDs = installedBundleIDs
    }

    public func scan() throws -> [ScanItem] {
        let vendors = Set(installedBundleIDs.map(Self.vendor))
        let walker = FileWalker(policy: policy)
        var items: [ScanItem] = []
        for folder in Self.folders {
            let entries =
                (try? FileManager.default.contentsOfDirectory(
                    at: home.appendingPathComponent(folder), includingPropertiesForKeys: nil)) ?? []
            for entry in entries {
                try Task.checkCancellation()
                guard let id = Self.bundleID(fromName: entry.lastPathComponent),
                    !id.lowercased().hasPrefix("com.apple."),
                    !vendors.contains(Self.vendor(id)),
                    policy.isDeletable(entry) == .allowed,
                    let stamp = FileStamp.read(entry)
                else { continue }
                items.append(
                    ScanItem(
                        url: entry, categoryID: "leftovers", risk: .review, mode: .trash,
                        reclaimableBytes: try walker.totalSize(entry), stamp: stamp))
            }
        }
        return items.sorted { $0.reclaimableBytes > $1.reclaimableBytes }
    }

    /// `com.foo.app.plist` -> `com.foo.app`, `group.com.foo.x` -> `com.foo.x`, `ABCDE12345.com.foo.x` -> `com.foo.x`.
    /// Nil when the name does not look like a reverse-DNS bundle ID with at least 3 parts.
    static func bundleID(fromName name: String) -> String? {
        var id = name
        for suffix in [".plist", ".savedState"] where id.hasSuffix(suffix) { id.removeLast(suffix.count) }
        if id.hasPrefix("group.") { id.removeFirst("group.".count) }
        let parts = id.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count >= 4, parts[0].count == 10, parts[0].allSatisfy({ $0.isUppercase || $0.isNumber }) {
            id = parts.dropFirst().joined(separator: ".")
        }
        let check = id.split(separator: ".", omittingEmptySubsequences: false)
        guard check.count >= 3,
            check.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" } })
        else { return nil }
        return id
    }

    /// First two reverse-DNS parts, lowercased: `com.google.Chrome` -> `com.google`.
    static func vendor(_ id: String) -> String {
        id.lowercased().split(separator: ".").prefix(2).joined(separator: ".")
    }

    public static func installedBundleIDs(in folders: [URL] = defaultAppFolders) -> Set<String> {
        var ids = Set<String>()
        func add(_ app: URL) {
            if app.pathExtension == "app", let id = Bundle(url: app)?.bundleIdentifier { ids.insert(id) }
        }
        for folder in folders {
            for item in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
                if item.pathExtension == "app" {
                    add(item)
                } else {
                    for nested in (try? FileManager.default.contentsOfDirectory(at: item, includingPropertiesForKeys: nil)) ?? [] {
                        add(nested)
                    }
                }
            }
        }
        return ids
    }

    public static var defaultAppFolders: [URL] {
        [
            URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/System/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]
    }
}
