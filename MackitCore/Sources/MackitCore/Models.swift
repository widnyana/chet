import Darwin
import Foundation

public enum Mackit {
    public static let version = "0.1.0"
}

public enum Risk: String, Sendable, Codable {
    case safe, review
}

public enum DeleteMode: String, Sendable, Codable {
    case permanent, trash
}

/// lstat snapshot of a path, taken at scan time and compared again before deletion.
public struct FileStamp: Hashable, Sendable {
    public let inode: UInt64
    public let size: Int64
    public let modified: Date
    public let links: UInt16
    public let isSymlink: Bool
    public let isRegularFile: Bool
    /// An iCloud / File Provider placeholder: no local data, and reading it would download it.
    public let isDataless: Bool

    /// `SF_DATALESS` in `st_flags` (sys/stat.h).
    static func isDataless(flags: UInt32) -> Bool {
        flags & 0x4000_0000 != 0
    }

    public static func read(_ url: URL) -> FileStamp? {
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return nil }
        let mtime = TimeInterval(st.st_mtimespec.tv_sec) + TimeInterval(st.st_mtimespec.tv_nsec) / 1e9
        return FileStamp(
            inode: UInt64(st.st_ino),
            size: Int64(st.st_size),
            modified: Date(timeIntervalSince1970: mtime),
            links: UInt16(st.st_nlink),
            isSymlink: (st.st_mode & S_IFMT) == S_IFLNK,
            isRegularFile: (st.st_mode & S_IFMT) == S_IFREG,
            isDataless: isDataless(flags: st.st_flags)
        )
    }
}

/// One reclaimable file or folder found by a scanner.
public struct ScanItem: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let categoryID: String
    public let risk: Risk
    public let mode: DeleteMode
    public let reclaimableBytes: Int64
    public let stamp: FileStamp
    /// App that owns the data, for example a browser. Cleaning is skipped while it runs.
    public let ownerBundleID: String?

    public init(
        url: URL, categoryID: String, risk: Risk, mode: DeleteMode, reclaimableBytes: Int64, stamp: FileStamp,
        ownerBundleID: String? = nil
    ) {
        self.url = url
        self.categoryID = categoryID
        self.risk = risk
        self.mode = mode
        self.reclaimableBytes = reclaimableBytes
        self.stamp = stamp
        self.ownerBundleID = ownerBundleID
    }
}
