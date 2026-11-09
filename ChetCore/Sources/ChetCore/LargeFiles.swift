import Foundation

/// Files that are very large, or large and untouched for a long time.
public struct LargeFileScanner: Sendable {
    public let policy: SafetyPolicy
    public var minSize: Int64 = 500_000_000
    public var oldAge: TimeInterval = 365 * 86_400
    public var minOldSize: Int64 = 50_000_000

    public init(policy: SafetyPolicy) {
        self.policy = policy
    }

    public func scan(_ roots: [URL], now: Date = Date()) throws -> [ScanItem] {
        var entries: [WalkEntry] = []
        let walker = FileWalker(policy: policy)
        for root in roots {
            try walker.walk(root) { entries.append($0) }
        }
        return select(from: entries, now: now)
    }

    /// Picks large and old files from files that were already walked.
    public func select(from entries: [WalkEntry], now: Date = Date()) -> [ScanItem] {
        entries.filter { entry in
            let old = now.timeIntervalSince(entry.stamp.modified) >= oldAge && entry.stamp.size >= minOldSize
            return entry.stamp.size >= minSize || old
        }
        .map { entry in
            ScanItem(
                url: entry.url, categoryID: "large-files", risk: .review, mode: .trash,
                reclaimableBytes: entry.reclaimableBytes, stamp: entry.stamp)
        }
        .sorted { $0.reclaimableBytes > $1.reclaimableBytes }
    }
}

public struct FolderNode: Sendable, Identifiable, Equatable {
    public var id: URL { url }
    public let url: URL
    public let size: Int64
    /// Largest first.
    public let children: [FolderNode]

    public init(url: URL, size: Int64, children: [FolderNode]) {
        self.url = url
        self.size = size
        self.children = children
    }

    /// Live tree merge: replaces the subtree at `update.url`, or appends it as a new child.
    /// Walker rollups arrive post-order, so an update always supersedes older data for its
    /// path; ancestors keep their own (older, larger-or-equal) totals until their own rollup
    /// lands. Pure, so the disk map's merge path is unit-testable without AppKit.
    public func merging(_ update: FolderNode) -> FolderNode {
        if url == update.url { return update }
        var children = self.children
        if let index = children.firstIndex(where: { $0.url.path == update.url.path }) {
            children[index] = update
        } else {
            children.append(update)
        }
        // Ancestors keep their own measured total, but never shrink below what their
        // children now account for (the home root grows as roots measure in).
        let size = max(size, children.reduce(0) { $0 + $1.size })
        return FolderNode(url: url, size: size, children: children.sorted { $0.size > $1.size })
    }

    /// Grafts a rollup that may arrive before its parent chain exists: descends from `self`
    /// (the tree root) along `update.url`'s path, replacing the subtree at the update's own
    /// position. Returns nil when some intermediate folder hasn't been measured yet — its
    /// own rollup will arrive later and carry this subtree with it. Pure.
    public func inserting(_ update: FolderNode) -> FolderNode? {
        if url.path == update.url.path { return update }
        let parent = update.url.deletingLastPathComponent()
        if parent.path == url.path {
            return merging(update)
        }
        guard
            let index = children.firstIndex(where: {
                update.url.path.hasPrefix($0.url.path + "/")
            }), let updated = children[index].inserting(update)
        else { return nil }
        var children = self.children
        children[index] = updated
        let size = max(size, children.reduce(0) { $0 + $1.size })
        return FolderNode(url: url, size: size, children: children.sorted { $0.size > $1.size })
    }
}

public enum FolderTree {
    /// Size tree of `root`, `maxDepth` levels deep. Files deeper than that count toward their ancestor.
    public static func build(_ root: URL, policy: SafetyPolicy, maxDepth: Int = 4) throws -> FolderNode {
        var sizes: [[String]: Int64] = [[]: 0]
        var children: [[String]: [[String]]] = [:]
        let base = root.standardizedFileURL.pathComponents.count
        try FileWalker(policy: policy).walk(root) { entry in
            let parts = Array(entry.url.standardizedFileURL.pathComponents.dropFirst(base).prefix(maxDepth))
            sizes[[], default: 0] += entry.reclaimableBytes
            for depth in parts.indices {
                let key = Array(parts[...depth])
                if sizes[key] == nil { children[Array(parts[..<depth]), default: []].append(key) }
                sizes[key, default: 0] += entry.reclaimableBytes
            }
        }
        func node(_ key: [String]) -> FolderNode {
            let url = key.reduce(root) { $0.appendingPathComponent($1) }
            let kids = (children[key] ?? []).map(node).sorted { $0.size > $1.size }
            return FolderNode(url: url, size: sizes[key] ?? 0, children: kids)
        }
        return node([])
    }
}
