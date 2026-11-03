import CryptoKit
import Foundation

public struct DuplicateGroup: Sendable, Identifiable {
    public var id: String { digest }
    public let digest: String
    public let size: Int64
    /// The copy that stays.
    public let keeper: WalkEntry
    /// Copies proposed for removal.
    public let duplicates: [WalkEntry]
    public var reclaimableBytes: Int64 { duplicates.reduce(0) { $0 + $1.reclaimableBytes } }
}

/// Exact duplicates: same size, then same first/last 16 KB, then same full SHA-256.
public struct DuplicateFinder: Sendable {
    public let policy: SafetyPolicy
    public var minSize: Int64 = 1_000_000
    /// A copy inside one of these folders is preferred as the keeper.
    public var keepFolders: [URL] = []

    public init(policy: SafetyPolicy) {
        self.policy = policy
    }

    // ponytail: hashes sequentially; the stage is disk-bound. Parallelize per size bucket if it measures slow.
    public func find(in roots: [URL]) throws -> [DuplicateGroup] {
        var bySize: [Int64: [WalkEntry]] = [:]
        var seenInodes = Set<UInt64>()
        let walker = FileWalker(policy: policy)
        for root in roots {
            try walker.walk(root) { entry in
                // Hard links share an inode: deleting one frees nothing.
                guard entry.stamp.size >= minSize, seenInodes.insert(entry.stamp.inode).inserted else { return }
                bySize[entry.stamp.size, default: []].append(entry)
            }
        }
        var groups: [DuplicateGroup] = []
        for (size, sameSize) in bySize where sameSize.count > 1 {
            for sameEdges in try grouped(sameSize, by: Self.edgeHash).values where sameEdges.count > 1 {
                for (digest, same) in try grouped(sameEdges, by: Self.fullHash) where same.count > 1 {
                    let keeper = pickKeeper(same)
                    // APFS clones share blocks with the keeper: deleting them frees almost nothing.
                    let duplicates = same.filter { $0.url != keeper.url && $0.reclaimableBytes >= size / 2 }
                    guard !duplicates.isEmpty else { continue }
                    groups.append(DuplicateGroup(digest: digest, size: size, keeper: keeper, duplicates: duplicates))
                }
            }
        }
        return groups.sorted { $0.reclaimableBytes > $1.reclaimableBytes }
    }

    private func grouped(_ entries: [WalkEntry], by hash: (URL) throws -> String) throws -> [String: [WalkEntry]] {
        var result: [String: [WalkEntry]] = [:]
        for entry in entries {
            try Task.checkCancellation()
            do {
                result[try hash(entry.url), default: []].append(entry)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue  // unreadable file: never reported as a duplicate
            }
        }
        return result
    }

    func pickKeeper(_ entries: [WalkEntry]) -> WalkEntry {
        let keepPaths = keepFolders.map { $0.standardizedFileURL.path + "/" }
        if let kept = entries.first(where: { entry in
            keepPaths.contains { entry.url.standardizedFileURL.path.hasPrefix($0) }
        }) {
            return kept
        }
        return entries.min { ($0.stamp.modified, $0.url.path) < ($1.stamp.modified, $1.url.path) } ?? entries[0]
    }

    static func edgeHash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        if let head = try handle.read(upToCount: 16_384) { hasher.update(data: head) }
        let end = try handle.seekToEnd()
        if end > 16_384 {
            try handle.seek(toOffset: end - 16_384)
            if let tail = try handle.read(upToCount: 16_384) { hasher.update(data: tail) }
        }
        return hex(hasher.finalize())
    }

    static func fullHash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: chunk)
        }
        return hex(hasher.finalize())
    }

    static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
