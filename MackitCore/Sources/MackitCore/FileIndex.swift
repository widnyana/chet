import Darwin
import Foundation
import Synchronization

/// One renderable copy of the walk's live counters. The walker refreshes it a few times a
/// second; `runningRootBytes` is what the in-flight top-level root has accumulated so far,
/// so the treemap can grow its block while that root is still being measured.
public struct ProgressSnapshot: Sendable, Equatable {
    public let files: Int
    public let bytes: Int64
    public let currentFolder: String
    public let rootsDone: Int
    public let rootsTotal: Int
    public let runningRootURL: URL?
    public let runningRootBytes: Int64

    public init(
        files: Int, bytes: Int64, currentFolder: String, rootsDone: Int, rootsTotal: Int,
        runningRootURL: URL?, runningRootBytes: Int64
    ) {
        self.files = files
        self.bytes = bytes
        self.currentFolder = currentFolder
        self.rootsDone = rootsDone
        self.rootsTotal = rootsTotal
        self.runningRootURL = runningRootURL
        self.runningRootBytes = runningRootBytes
    }
}

/// Live scan counters. The walker writes them, the UI reads them about 10 times a second
/// (relaxed atomics, like ncdu's `files_seen` and `bytes_seen`).
public final class ScanProgress: Sendable {
    private let filesSeen = Atomic<Int>(0)
    private let bytesSeen = Atomic<Int64>(0)
    private let folder = Mutex<String>("")

    public init() {}

    public var files: Int { filesSeen.load(ordering: .relaxed) }
    public var bytes: Int64 { bytesSeen.load(ordering: .relaxed) }
    public var currentFolder: String { folder.withLock { $0 } }

    func add(files: Int, bytes: Int64) {
        _ = filesSeen.add(files, ordering: .relaxed)
        _ = bytesSeen.add(bytes, ordering: .relaxed)
    }

    func enter(_ path: String) {
        folder.withLock { $0 = path }
    }

    /// Per-root-start notification, if a builder installed one: (root, done, total).
    let rootStart = Mutex<(@Sendable (URL, Int, Int) -> Void)?>(nil)
}

public struct TaggedFolder: Sendable, Equatable {
    public let url: URL
    public let bytes: Int64
}

/// Result of one metadata-only pass over folders.
public struct FileIndex: Sendable {
    /// Files later steps need: 1 MB and up, or images and videos. Never inside packages, `.git`
    /// or tagged cache folders, never dataless, and allowed by the safety policy.
    public var candidates: [WalkEntry] = []
    /// Folder size tree per root, in allocated bytes: folders, and files of 1 MB and up.
    public var trees: [FolderNode] = []
    /// Folders holding a valid `CACHEDIR.TAG` (https://bford.info/cachedir/).
    public var taggedCaches: [TaggedFolder] = []
    /// Directory entries seen (files, folders, links).
    public var entriesSeen = 0
}

public struct FileIndexBuilder: Sendable {
    public let policy: SafetyPolicy
    public let progress: ScanProgress
    /// Called once per measured top-level root, with its finished node.
    public var onRootMeasured: (@Sendable (FolderNode) -> Void)?
    /// Called a few times a second while the walk runs, with live counters and the
    /// in-flight root's growing byte total.
    public var onProgress: (@Sendable (ProgressSnapshot) -> Void)?
    /// Folder levels kept in `FileIndex.trees`; deeper folders only add to their ancestors.
    public var maxDepth = 6
    public var candidateMinSize: Int64 = 1_000_000
    public var collectCandidates = true

    static let packageExtensions: Set<String> = [
        "app", "photoslibrary", "framework", "bundle", "plugin", "kext", "appex", "xpc", "musiclibrary",
        "tvlibrary", "imovielibrary", "fcpbundle",
    ]
    static let cacheTagSignature = Array("Signature: 8a477f597d28d172789f06886806bc55".utf8)

    public init(policy: SafetyPolicy, progress: ScanProgress = ScanProgress()) {
        self.policy = policy
        self.progress = progress
    }

    public func build(roots: [URL]) throws -> FileIndex {
        var index = FileIndex()
        var seenInodes = Set<UInt64>()
        let media = SimilarPhotos.extensions.union(SimilarVideos.extensions)
        let total = roots.count
        for (rootIndex, root) in roots.enumerated() {
            let fd = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { continue }
            defer { close(fd) }
            var st = stat()
            guard fstat(fd, &st) == 0 else { continue }
            let bytesAtStart = progress.bytes
            progress.enter(root.path)
            nonisolated(unsafe) var lastTick = DispatchTime.now().uptimeNanoseconds
            // The in-flight root is reported by URL so the callback can pick up its
            // growing total from the shared counters.
            let runningRoot = root
            let node = try walk(
                fd: fd, url: root, depth: 0, device: st.st_dev, excluded: false, media: media,
                seenInodes: &seenInodes, index: &index,
                tick: { files, bytes, folder in
                    let now = DispatchTime.now().uptimeNanoseconds
                    guard now - lastTick >= 250_000_000 else { return }  // ~4 Hz
                    lastTick = now
                    self.onProgress?(
                        ProgressSnapshot(
                            files: files, bytes: bytes, currentFolder: folder,
                            rootsDone: rootIndex, rootsTotal: total,
                            runningRootURL: runningRoot,
                            runningRootBytes: max(0, bytes - bytesAtStart)))
                })
            onRootMeasured?(node)
            index.trees.append(node)
        }
        return index
    }

    /// Allocated bytes of a file or folder tree (hard links once, dataless files 0), in one pass.
    public static func allocatedSize(of url: URL) -> Int64 {
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return 0 }
        if (st.st_mode & S_IFMT) == S_IFREG {
            return FileStamp.isDataless(flags: st.st_flags) ? 0 : Int64(st.st_blocks) * 512
        }
        guard (st.st_mode & S_IFMT) == S_IFDIR else { return 0 }
        var builder = FileIndexBuilder(policy: SafetyPolicy(home: url.deletingLastPathComponent()))
        builder.maxDepth = 0
        builder.collectCandidates = false
        return (try? builder.build(roots: [url]))?.trees.first?.size ?? 0
    }

    private func walk(
        fd: Int32, url: URL, depth: Int, device: dev_t, excluded: Bool, media: Set<String>,
        seenInodes: inout Set<UInt64>, index: inout FileIndex,
        tick: @Sendable (Int, Int64, String) -> Void
    ) throws -> FolderNode {
        try Task.checkCancellation()
        progress.enter(url.path)
        let tagged = !excluded && Self.isCacheDir(fd)
        let noCandidates = excluded || tagged || !collectCandidates
        var total: Int64 = 0
        var children: [FolderNode] = []
        var entries = 0
        try Self.forEachEntry(fd) { entry in
            entries += 1
            switch entry.kind {
            case .directory:
                guard entry.device == device else { return }  // another filesystem
                let childFD = openat(fd, entry.name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard childFD >= 0 else { return }
                defer { close(childFD) }
                let ext = (entry.name as NSString).pathExtension.lowercased()
                let node = try walk(
                    fd: childFD, url: url.appendingPathComponent(entry.name, isDirectory: true), depth: depth + 1,
                    device: device,
                    excluded: noCandidates || entry.name == ".git" || Self.packageExtensions.contains(ext),
                    media: media, seenInodes: &seenInodes, index: &index, tick: tick)
                total += node.size
                if depth < maxDepth { children.append(node) }
            case .file:
                if entry.isDataless { return }
                // Hard links share an inode: count the data once.
                if entry.links > 1, !seenInodes.insert(entry.inode).inserted { return }
                total += entry.allocatedSize
                progress.add(files: 0, bytes: entry.allocatedSize)
                let big = entry.size >= candidateMinSize
                let fileURL = url.appendingPathComponent(entry.name, isDirectory: false)
                if big && depth < maxDepth {
                    children.append(FolderNode(url: fileURL, size: entry.allocatedSize, children: []))
                }
                let ext = (entry.name as NSString).pathExtension.lowercased()
                guard !noCandidates, big || media.contains(ext), policy.isDeletable(fileURL) == .allowed else {
                    return
                }
                let stamp = FileStamp(
                    inode: entry.inode, size: entry.size, modified: entry.modified, links: entry.links,
                    isSymlink: false, isRegularFile: true, isDataless: false)
                index.candidates.append(
                    WalkEntry(
                        url: fileURL, stamp: stamp,
                        reclaimableBytes: entry.hasPrivateSize
                            ? entry.privateSize
                            : (SizeProbe.reclaimableBytes(fileURL) ?? entry.allocatedSize)))
            case .other:
                return
            }
        }
        progress.add(files: entries, bytes: 0)
        index.entriesSeen += entries
        tick(progress.files, progress.bytes, url.path)
        if tagged { index.taggedCaches.append(TaggedFolder(url: url, bytes: total)) }
        return FolderNode(url: url, size: total, children: children.sorted { $0.size > $1.size })
    }

    /// True when the folder holds a `CACHEDIR.TAG` starting with the spec signature (ncdu `isCacheDir`).
    static func isCacheDir(_ fd: Int32) -> Bool {
        let tag = openat(fd, "CACHEDIR.TAG", O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard tag >= 0 else { return false }
        defer { close(tag) }
        var buffer = [UInt8](repeating: 0, count: cacheTagSignature.count)
        let count = read(tag, &buffer, buffer.count)
        return count == buffer.count && buffer == cacheTagSignature
    }

    struct Entry {
        enum Kind { case file, directory, other }
        let name: String
        let kind: Kind
        let device: dev_t
        let modified: Date
        let flags: UInt32
        let inode: UInt64
        let links: UInt16
        let size: Int64
        let allocatedSize: Int64
        /// APFS private size (blocks not shared with clones); 0 is valid data for one member
        /// of a full clone pair. Only meaningful when `hasPrivateSize`.
        let privateSize: Int64
        let hasPrivateSize: Bool
        var isDataless: Bool { FileStamp.isDataless(flags: flags) }
    }

    /// Reads a folder in batches with `getattrlistbulk`. With FSOPT_PACK_INVAL_ATTRS every requested
    /// attribute is present in each record, so the layout is fixed:
    /// length, returned attribute_set_t (20 bytes), error, name attrreference, devid, objtype,
    /// modtime timespec, flags, fileid, then file attributes linkcount, totalsize, allocsize,
    /// and — with FSOPT_ATTR_CMN_EXTENDED, required for fork attributes — the privatesize.
    static func forEachEntry(_ fd: Int32, _ body: (Entry) throws -> Void) throws {
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        // RETURNED_ATTRS | ERROR | NAME | DEVID | OBJTYPE | MODTIME | FLAGS | FILEID
        request.commonattr =
            0x8000_0000 | 0x2000_0000 | 0x0000_0001 | 0x0000_0002 | 0x0000_0008 | 0x0000_0400
            | 0x0004_0000 | 0x0200_0000
        // LINKCOUNT | TOTALSIZE | ALLOCSIZE
        request.fileattr = 0x1 | 0x2 | 0x4
        // ATTR_CMNEXT_PRIVATESIZE — a fork attribute, only carried with FSOPT_ATTR_CMN_EXTENDED.
        request.forkattr = 0x0000_0008
        let capacity = 64 * 1024
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: 8)
        defer { buffer.deallocate() }
        while true {
            try Task.checkCancellation()
            // FSOPT_PACK_INVAL_ATTRS | FSOPT_ATTR_CMN_EXTENDED
            let count = getattrlistbulk(fd, &request, buffer, capacity, 0x8 | 0x20)
            if count <= 0 { return }  // 0: done, -1: unreadable folder, stop here
            var record = UnsafeRawPointer(buffer)
            for _ in 0..<count {
                let length = Int(record.loadUnaligned(as: UInt32.self))
                let hasPrivateSize = (record + 4 + 16).loadUnaligned(as: UInt32.self) & 0x0000_0008 != 0
                var cursor = record + 4 + 20
                let error = cursor.loadUnaligned(as: UInt32.self)
                cursor += 4
                let nameReference = cursor
                let nameOffset = Int(cursor.loadUnaligned(as: Int32.self))
                cursor += 8
                let device = cursor.loadUnaligned(as: Int32.self)
                cursor += 4
                let type = cursor.loadUnaligned(as: UInt32.self)
                cursor += 4
                let seconds = cursor.loadUnaligned(as: Int.self)
                let nanoseconds = (cursor + 8).loadUnaligned(as: Int.self)
                cursor += 16
                let flags = cursor.loadUnaligned(as: UInt32.self)
                cursor += 4
                let inode = cursor.loadUnaligned(as: UInt64.self)
                cursor += 8
                let links = cursor.loadUnaligned(as: UInt32.self)
                cursor += 4
                let size = cursor.loadUnaligned(as: Int64.self)
                cursor += 8
                let allocated = cursor.loadUnaligned(as: Int64.self)
                cursor += 8
                let privateSize = cursor.loadUnaligned(as: Int64.self)
                let name = String(cString: (nameReference + nameOffset).assumingMemoryBound(to: CChar.self))
                record += length
                guard error == 0 else { continue }
                // fsobj_type_t: VREG = 1, VDIR = 2.
                let kind: Entry.Kind = type == 1 ? .file : type == 2 ? .directory : .other
                try body(
                    Entry(
                        name: name, kind: kind, device: device,
                        modified: Date(
                            timeIntervalSince1970: TimeInterval(seconds) + TimeInterval(nanoseconds) / 1e9),
                        flags: flags, inode: inode, links: UInt16(clamping: links), size: size,
                        allocatedSize: allocated, privateSize: privateSize, hasPrivateSize: hasPrivateSize))
            }
        }
    }
}
