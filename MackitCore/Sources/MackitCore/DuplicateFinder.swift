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
    /// Full-content hash used before the byte-for-byte confirmation.
    public var hasher: Hasher = .sha256
    /// Test hook: replaces the full-content hash.
    var fullHashOverride: (@Sendable (URL) throws -> String)? = nil

    public enum Hasher: Sendable {
        case sha256, gpu
    }

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
                for (digest, sameHash) in try grouped(sameEdges, by: fullHasher()) where sameHash.count > 1 {
                    for same in try confirmed(sameHash) where same.count > 1 {
                        let keeper = pickKeeper(same)
                        // APFS clones share blocks with the keeper: deleting them frees almost nothing.
                        let duplicates = same.filter { $0.url != keeper.url && $0.reclaimableBytes >= size / 2 }
                        guard !duplicates.isEmpty else { continue }
                        groups.append(
                            DuplicateGroup(digest: digest, size: size, keeper: keeper, duplicates: duplicates))
                    }
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

    func fullHasher() -> (URL) throws -> String {
        if let fullHashOverride { return fullHashOverride }
        if hasher == .gpu, let context = GPUContext.shared {
            let gpu = GPUHasher(context: context)
            return { try gpu.digest($0) }
        }
        return Self.fullHash
    }

    /// Splits same-hash entries into groups whose bytes are really identical, so a hash collision
    /// (or a GPU bug) can never mark a different file as a duplicate.
    func confirmed(_ entries: [WalkEntry]) throws -> [[WalkEntry]] {
        var groups: [[WalkEntry]] = []
        for entry in entries {
            if let index = try groups.firstIndex(where: { try Self.sameBytes($0[0].url, entry.url) }) {
                groups[index].append(entry)
            } else {
                groups.append([entry])
            }
        }
        return groups
    }

    static func sameBytes(_ a: URL, _ b: URL) throws -> Bool {
        guard let left = try? FileHandle(forReadingFrom: a), let right = try? FileHandle(forReadingFrom: b) else {
            return false
        }
        defer {
            try? left.close()
            try? right.close()
        }
        while true {
            try Task.checkCancellation()
            let x = (try? left.read(upToCount: 1 << 20)) ?? Data()
            let y = (try? right.read(upToCount: 1 << 20)) ?? Data()
            if x != y { return false }
            if x.isEmpty { return true }
        }
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
