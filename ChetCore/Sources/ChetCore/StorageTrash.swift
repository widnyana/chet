import Darwin
import Foundation

/// One folder the Storage screen collected. Bytes are the size the map measured at
/// collect time, so the confirmation never changes under the user after a rescan.
public struct StorageEntry: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let name: String
    public let bytes: Int64

    public init(url: URL, name: String? = nil, bytes: Int64) {
        self.url = url
        self.name = name ?? url.lastPathComponent
        self.bytes = bytes
    }
}

/// Breadcrumb arithmetic. The path view is the root plus one entry per crumb, so a
/// crumb index is exactly the number of stack entries to keep below it.
public enum StoragePath {
    public static func trimmed<T>(_ stack: [T], to crumb: Int) -> [T] {
        if crumb <= 0 { return [] }
        if crumb >= stack.count { return stack }
        return Array(stack.prefix(crumb))
    }
}

public struct StorageTrashResult: Sendable, Equatable {
    public struct Failure: Identifiable, Sendable, Equatable {
        public var id: URL { url }
        public let url: URL
        public let name: String
        public let reason: String

        public init(url: URL, name: String, reason: String) {
            self.url = url
            self.name = name
            self.reason = reason
        }
    }

    public var dryRun = false
    public var moved: [StorageEntry] = []
    public var wouldMove: [StorageEntry] = []
    public var failed: [Failure] = []
    public var freedBytes: Int64 = 0
}

/// Moves collected folders to the Trash. Every entry is re-checked at trash time with
/// the same colours as the rest of the app: protected trees, symlinks, mount points,
/// and app bundles outside the two Applications folders stay refused.
///
/// App bundles are the one allow-listed operation, mirroring `AppUninstaller`: the
/// safety policy refuses every `.app` path by design, so an `.app` directly inside an
/// Applications folder is allowed here and nothing else is.
public struct StorageTrasher: Sendable {
    public let policy: SafetyPolicy
    public let appFolders: [URL]
    public let dryRun: Bool
    public var trash: @Sendable (URL) throws -> Void

    public init(
        policy: SafetyPolicy,
        appFolders: [URL]? = nil,
        dryRun: Bool,
        trash: @escaping @Sendable (URL) throws -> Void = { url in
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
    ) {
        self.policy = policy
        self.appFolders =
            appFolders
            ?? [
                URL(fileURLWithPath: "/Applications"),
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
            ]
        self.dryRun = dryRun
        self.trash = trash
    }

    /// Final gate before the sheet appears and again immediately before each move.
    public func check(_ entry: StorageEntry) -> Verdict {
        let url = entry.url.standardizedFileURL
        guard let stamp = FileStamp.read(url) else { return .denied("missing") }
        if stamp.isSymlink { return .denied("symlink") }
        if policy.isProtectedPath(url) { return .denied("protected folder") }

        if isAppBundle(url), isInside(url, anyOf: appFolders) {
            // The app bundle allowance, no further path rules.
        } else {
            let verdict = policy.isDeletable(url)
            guard verdict == .allowed else { return verdict }
        }

        // A mount point cannot be trashed as a folder, and a folder this user cannot
        // write to would fail late. Both are named before the sheet, not after.
        var st = stat()
        var parent = stat()
        let path = url.path
        if lstat(path, &st) == 0, lstat((path as NSString).deletingLastPathComponent, &parent) == 0,
            st.st_dev != parent.st_dev
        {
            return .denied("mount point")
        }
        if !FileManager.default.isWritableFile(atPath: (path as NSString).deletingLastPathComponent) {
            return .denied("needs administrator")
        }
        return .allowed
    }

    public func trash(_ entries: [StorageEntry]) -> StorageTrashResult {
        var result = StorageTrashResult(dryRun: dryRun)
        var failureErrno: Int32?
        VerboseLog.flush()
        // A parent and its child cannot both be moved. Keep the shallowest entry and
        // let the child go with it.
        for entry in Self.pruned(entries) {
            switch check(entry) {
            case .denied(let reason):
                result.failed.append(.init(url: entry.url, name: entry.name, reason: reason))
            case .allowed:
                if dryRun {
                    result.wouldMove.append(entry)
                    continue
                }
                do {
                    try trash(entry.url)
                    result.moved.append(entry)
                    result.freedBytes += max(0, entry.bytes)
                } catch {
                    let failure = error as NSError
                    if failure.domain == NSPOSIXErrorDomain { failureErrno = Int32(failure.code) }
                    result.failed.append(
                        .init(url: entry.url, name: entry.name, reason: error.localizedDescription))
                }
            }
        }
        VerboseLog.event(
            .info, .storage, .storageTrashMove,
            .count(.entries, result.moved.count),
            .bytes(.bytes, result.freedBytes),
            .code(.outcome, .outcomeMoved),
            failureErrno.map { LogField.status(.errno, $0) })
        return result
    }

    /// Drops nested entries so a parent is moved once.
    static func pruned(_ entries: [StorageEntry]) -> [StorageEntry] {
        let sorted = entries.sorted { $0.url.path.count < $1.url.path.count }
        var kept: [String] = []
        var out: [StorageEntry] = []
        for entry in sorted {
            let path = FS.canonicalPath(entry.url)
            if kept.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { continue }
            kept.append(path)
            out.append(entry)
        }
        return out
    }

    private func isAppBundle(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "app"
            && FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/Info.plist").path)
    }

    private func isInside(_ url: URL, anyOf folders: [URL]) -> Bool {
        let path = FS.canonicalPath(url)
        return folders.contains { folder in
            let base = FS.canonicalPath(folder)
            return path.hasPrefix(base + "/")
        }
    }
}
