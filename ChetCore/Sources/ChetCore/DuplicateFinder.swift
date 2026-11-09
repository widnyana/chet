import CryptoKit
import Darwin
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
        var entries: [WalkEntry] = []
        let walker = FileWalker(policy: policy)
        for root in roots {
            try walker.walk(root) { entries.append($0) }
        }
        return try find(entries: entries)
    }

    /// Groups files that were already walked, for example `FileIndex.candidates`.
    public func find(entries: [WalkEntry]) throws -> [DuplicateGroup] {
        var bySize: [Int64: [WalkEntry]] = [:]
        var seenInodes = Set<UInt64>()
        for entry in entries {
            // Hard links share an inode: deleting one frees nothing.
            guard entry.stamp.size >= minSize, seenInodes.insert(entry.stamp.inode).inserted else { continue }
            bySize[entry.stamp.size, default: []].append(entry)
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

    /// One 1 MiB chunk buffer for a hashing pass. POSIX reads keep Foundation's
    /// autoreleased `NSData` out of the long synchronous duplicate step.
    private static func withBuffer<T>(_ body: (UnsafeMutableRawPointer) throws -> T) rethrows -> T {
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: 1 << 20, alignment: 8)
        defer { buffer.deallocate() }
        return try body(buffer)
    }

    private static func openFile(_ url: URL) throws -> Int32 {
        let fd = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return open(path, O_RDONLY | O_CLOEXEC)
        }
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        _ = fcntl(fd, F_NOCACHE, 1)
        return fd
    }

    private static func readChunk(_ fd: Int32, _ buffer: UnsafeMutableRawPointer, _ count: Int)
        -> Int
    {
        while true {
            let got = read(fd, buffer, count)
            if got >= 0 { return got }
            if errno != EINTR { return -1 }
        }
    }

    static func sameBytes(_ a: URL, _ b: URL) throws -> Bool {
        let left = try? openFile(a)
        let right = try? openFile(b)
        guard let left, let right else {
            if let left { close(left) }
            if let right { close(right) }
            return false
        }
        defer {
            close(left)
            close(right)
        }
        let first = UnsafeMutableRawPointer.allocate(byteCount: 1 << 20, alignment: 8)
        let second = UnsafeMutableRawPointer.allocate(byteCount: 1 << 20, alignment: 8)
        defer {
            first.deallocate()
            second.deallocate()
        }
        while true {
            try Task.checkCancellation()
            let x = readChunk(left, first, 1 << 20)
            let y = readChunk(right, second, 1 << 20)
            if x < 0 || y < 0 || x != y { return false }
            if x == 0 { return true }
            if memcmp(first, second, x) != 0 { return false }
        }
    }

    static func edgeHash(_ url: URL) throws -> String {
        let fd = try openFile(url)
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        var hasher = SHA256()
        try withBuffer { buffer in
            let head = readChunk(fd, buffer, 16_384)
            if head < 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            if head > 0 {
                hasher.update(bufferPointer: UnsafeRawBufferPointer(start: buffer, count: head))
            }
            if info.st_size > 16_384 {
                guard lseek(fd, info.st_size - 16_384, SEEK_SET) >= 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                let tail = readChunk(fd, buffer, 16_384)
                if tail < 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                if tail > 0 {
                    hasher.update(bufferPointer: UnsafeRawBufferPointer(start: buffer, count: tail))
                }
            }
        }
        return hex(hasher.finalize())
    }

    static func fullHash(_ url: URL) throws -> String {
        let fd = try openFile(url)
        defer { close(fd) }
        var hasher = SHA256()
        try withBuffer { buffer in
            while true {
                try Task.checkCancellation()
                let count = readChunk(fd, buffer, 1 << 20)
                if count < 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                if count == 0 { break }
                hasher.update(bufferPointer: UnsafeRawBufferPointer(start: buffer, count: count))
            }
        }
        return hex(hasher.finalize())
    }

    private static let hexDigits: [UInt8] = Array("0123456789abcdef".utf8)

    static func hex(_ digest: SHA256.Digest) -> String {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(64)
        for byte in digest {
            bytes.append(hexDigits[Int(byte >> 4)])
            bytes.append(hexDigits[Int(byte & 0x0F)])
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
