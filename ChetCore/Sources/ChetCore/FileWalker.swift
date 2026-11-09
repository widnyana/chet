import Darwin
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
    ///
    /// One `getattrlistbulk` per folder, the same reader the scan uses: file stamps come from the
    /// directory records, so a folder costs one syscall per batch instead of a `lstat` per entry.
    public func walk(_ root: URL, _ visit: (WalkEntry) throws -> Void) throws {
        if let stamp = FileStamp.read(root) {
            if stamp.isSymlink { return }
            if stamp.isRegularFile {
                guard !stamp.isDataless else { return }
                try emit(root, stamp, visit)
                return
            }
        }
        let rootFD = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard rootFD >= 0 else { return }
        var status = stat()
        guard fstat(rootFD, &status) == 0 else {
            close(rootFD)
            return
        }
        let rootDevice = status.st_dev

        var stack: [(fd: Int32, url: URL)] = [(rootFD, root)]
        defer {
            // A throw leaves queued folders open; every descriptor is closed exactly once.
            while let pending = stack.popLast() { close(pending.fd) }
        }

        while let current = stack.popLast() {
            defer { close(current.fd) }
            let outcome = try FileIndexBuilder.forEachEntry(
                current.fd, stop: { Task.isCancelled },
                { entry in
                    try Task.checkCancellation()
                    // Another volume: not this walk's disk, and nothing below it is either.
                    guard entry.device == rootDevice else { return }
                    let url = current.url.appendingPathComponent(entry.name)
                    switch entry.kind {
                    case .directory:
                        guard entry.name != ".git",
                            !FileIndexBuilder.packageExtensions.contains(url.pathExtension.lowercased())
                        else { return }
                        let fd = openat(
                            current.fd, entry.name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                        // An unreadable folder is skipped, the same way the enumerator swallowed errors.
                        guard fd >= 0 else { return }
                        stack.append((fd, url))
                    case .file:
                        guard !entry.isDataless else { return }
                        try emit(url, FileIndexBuilder.makeStamp(entry), visit)
                    case .other:
                        // Symlinks, sockets, devices: never visited, never followed.
                        return
                    }
                })
            if outcome == Int32(EINTR) { throw CancellationError() }
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
