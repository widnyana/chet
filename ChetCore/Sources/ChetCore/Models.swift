import Darwin
import Foundation

public enum Chet {
    public static let version = "0.1.0"
}

public enum Risk: String, Sendable, Codable {
    case safe, review, informational
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
    /// Root-owned data. The cleaner routes it to the privileged helper instead of removing it.
    public let requiresAdmin: Bool
    /// Tool behind a build directory, for example `Rust target`. Nil outside build artifacts.
    public let kind: String?
    /// What `reclaimableBytes` measures. `.allocated` unless the producer walked the index.
    public let sizeBasis: SizeBasis

    public init(
        url: URL, categoryID: String, risk: Risk, mode: DeleteMode, reclaimableBytes: Int64, stamp: FileStamp,
        ownerBundleID: String? = nil, requiresAdmin: Bool = false, kind: String? = nil,
        sizeBasis: SizeBasis = .allocated
    ) {
        self.url = url
        self.categoryID = categoryID
        self.risk = risk
        self.mode = mode
        self.reclaimableBytes = reclaimableBytes
        self.stamp = stamp
        self.ownerBundleID = ownerBundleID
        self.requiresAdmin = requiresAdmin
        self.kind = kind
        self.sizeBasis = sizeBasis
    }

    public func resolved(with other: ScanItem) -> ScanItem {
        guard url == other.url else { return self }
        let mergedBasis: SizeBasis =
            sizeBasis == .allocated || other.sizeBasis == .allocated ? .allocated : .reclaimable
        let chosen: ScanItem
        if other.conservation != conservation {
            chosen = other.conservation > conservation ? other : self
        } else if other.mode != mode {
            chosen = other.mode == .trash ? other : self
        } else {
            chosen = self
        }
        return chosen.sizeBasis == mergedBasis ? chosen : chosen.withSizeBasis(mergedBasis)
    }

    private func withSizeBasis(_ basis: SizeBasis) -> ScanItem {
        ScanItem(
            url: url, categoryID: categoryID, risk: risk, mode: mode, reclaimableBytes: reclaimableBytes,
            stamp: stamp, ownerBundleID: ownerBundleID, requiresAdmin: requiresAdmin, kind: kind,
            sizeBasis: basis)
    }

    private var conservation: Int {
        switch risk {
        case .safe: 0
        case .review: 1
        case .informational: 2
        }
    }
}

public struct ScanLedger: Sendable {
    public private(set) var itemsByURL: [URL: ScanItem] = [:]
    public private(set) var totalBytes: Int64
    public private(set) var selected: Set<URL> = []
    public private(set) var selectedBytes: Int64 = 0
    private var bytesByURL: [URL: Int64] = [:]

    public init(totalBytes: Int64 = 0) {
        self.totalBytes = totalBytes
    }

    public func item(for url: URL) -> ScanItem? {
        itemsByURL[url]
    }

    public mutating func record(_ item: ScanItem) {
        guard let existing = itemsByURL[item.url] else {
            itemsByURL[item.url] = item
            bytesByURL[item.url] = item.reclaimableBytes
            totalBytes += item.reclaimableBytes
            return
        }
        let resolved = existing.resolved(with: item)
        guard resolved != existing else { return }
        let previous = bytesByURL[item.url] ?? existing.reclaimableBytes
        let delta = resolved.reclaimableBytes - previous
        bytesByURL[item.url] = resolved.reclaimableBytes
        totalBytes += delta
        if selected.contains(item.url) { selectedBytes += delta }
        itemsByURL[item.url] = resolved
    }

    public mutating func selectIfSafe(_ url: URL) {
        if item(for: url)?.risk == .safe {
            select(url)
        } else {
            deselect(url)
        }
    }

    public mutating func select(_ url: URL) {
        guard selected.insert(url).inserted, let bytes = bytesByURL[url] else { return }
        selectedBytes += bytes
    }

    public mutating func deselect(_ url: URL) {
        guard selected.remove(url) != nil, let bytes = bytesByURL[url] else { return }
        selectedBytes -= bytes
    }

    @discardableResult
    public mutating func remove(_ url: URL) -> Int64? {
        guard let item = itemsByURL.removeValue(forKey: url) else { return nil }
        let bytes = bytesByURL.removeValue(forKey: url) ?? item.reclaimableBytes
        totalBytes -= bytes
        if selected.remove(url) != nil { selectedBytes -= bytes }
        return bytes
    }

    public mutating func removeAll() {
        itemsByURL.removeAll()
        bytesByURL.removeAll()
        totalBytes = 0
        selected.removeAll()
        selectedBytes = 0
    }
}
