import Foundation

/// Synchronous filesystem helpers for the off-main-thread feature scans. Sizes are allocated
/// bytes (space actually on disk), matching the rest of the app.
enum FS {
    struct Usage: Equatable {
        var size: Int64 = 0
        var files: Int = 0
    }

    private static let keys: Set<URLResourceKey> = [
        .isDirectoryKey, .totalFileAllocatedSizeKey, .isSymbolicLinkKey,
    ]

    /// Allocated size of a file, or of a folder's recursive contents. Unreadable entries are
    /// skipped, so the result is a floor, never an overcount. Symlinks are never followed, so a
    /// link into an ancestor cannot create a counting cycle.
    static func usage(_ path: String) -> Usage {
        var usage = Usage()
        walk(URL(fileURLWithPath: path), into: &usage)
        return usage
    }

    private static func walk(_ url: URL, into usage: inout Usage) {
        guard let values = try? url.resourceValues(forKeys: keys) else { return }
        if values.isSymbolicLink == true { return }
        if values.isDirectory == true {
            let children =
                (try? FileManager.default.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: Array(keys), options: [])) ?? []
            for child in children { walk(child, into: &usage) }
        } else {
            usage.size += Int64(values.totalFileAllocatedSize ?? 0)
            usage.files += 1
        }
    }

    /// Immediate child names of a folder, or nil when it cannot be read.
    static func list(_ path: String) -> [String]? {
        try? FileManager.default.contentsOfDirectory(atPath: path)
    }
}
