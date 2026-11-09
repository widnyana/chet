import Foundation

/// One regular file found by FileWalker.
public struct WalkEntry: Sendable {
    public let url: URL
    public let stamp: FileStamp
    public let reclaimableBytes: Int64
}

public struct FileWalker: Sendable {
    public let policy: SafetyPolicy

    public init(policy: SafetyPolicy) {
        self.policy = policy
    }

    /// Visits regular files under `root` (or `root` itself if it is a file). Never follows symlinks,
    /// skips package contents and other volumes, skips files the policy denies.
    /// Throws CancellationError when the current task is cancelled.
    public func walk(_ root: URL, _ visit: (WalkEntry) throws -> Void) throws {
        if let stamp = FileStamp.read(root), stamp.isRegularFile, !stamp.isDataless {
            try emit(root, stamp, visit)
            return
        }
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .volumeIdentifierKey]
        let rootVolume = (try? root.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? NSObject
        guard
            let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants],
                errorHandler: { _, _ in true })
        else { return }
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isSymbolicLink == true { continue }
            if let volume = values.volumeIdentifier as? NSObject, let rootVolume, volume != rootVolume {
                enumerator.skipDescendants()
                continue
            }
            guard values.isRegularFile == true, let stamp = FileStamp.read(url), !stamp.isDataless else { continue }
            try emit(url, stamp, visit)
        }
    }

    /// Reclaimable bytes under `root`, counting each hard-linked inode once.
    public func totalSize(_ root: URL) throws -> Int64 {
        var seen = Set<UInt64>()
        var total: Int64 = 0
        try walk(root) { entry in
            if entry.stamp.links > 1, !seen.insert(entry.stamp.inode).inserted { return }
            total += entry.reclaimableBytes
        }
        return total
    }

    private func emit(_ url: URL, _ stamp: FileStamp, _ visit: (WalkEntry) throws -> Void) throws {
        guard policy.isDeletable(url) == .allowed else { return }
        let bytes = SizeProbe.reclaimableBytes(url) ?? stamp.size
        try visit(WalkEntry(url: url, stamp: stamp, reclaimableBytes: bytes))
    }
}
