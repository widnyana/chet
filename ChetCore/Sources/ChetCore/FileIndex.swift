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
}

public struct TaggedFolder: Sendable, Equatable {
    public let url: URL
    public let bytes: Int64
}

/// A folder the walk could not read; totals remain best-known (ncdu's error-as-node semantics).
public struct WalkError: Sendable, Equatable {
    public let url: URL
    public let errno: Int32
}

/// Result of one metadata-only pass over folders.
public struct FileIndex: Sendable {
    /// Files later steps need: 1 MB and up, or images and videos. Never inside packages, `.git`
    /// or tagged cache folders, never dataless, and allowed by the scan gate.
    public var candidates: [WalkEntry] = []
    /// Folder size tree per root, in allocated bytes (`.allocated` basis): folders, and files of
    /// 1 MB and up. Blocks shared by APFS clones count for each clone; per-file private size is
    /// the clone-aware signal.
    public var trees: [FolderNode] = []
    /// What `trees` measure; see `SizeBasis`.
    public var treeSizeBasis: SizeBasis = .allocated
    /// Folders holding a valid `CACHEDIR.TAG` (https://bford.info/cachedir/).
    public var taggedCaches: [TaggedFolder] = []
    /// Folders that could not be read (open or readdir failed); sizes are best-known.
    public var readErrors: [WalkError] = []
    /// Directory entries seen (files, folders, links).
    public var entriesSeen = 0
}

/// Cancellation flag shared with the walk; set from the owning task's cancellation handler.
public final class CancelState: Sendable {
    private let flag = Atomic<Bool>(false)
    public init() {}
    public func cancel() { flag.store(true, ordering: .relaxed) }
    public var isCancelled: Bool { flag.load(ordering: .relaxed) }
}

/// Throttles a callback to one call per interval across worker threads.
final class TickGate: Sendable {
    private let last = Mutex<UInt64>(0)

    func take(now: UInt64, interval: UInt64) -> Bool {
        last.withLock { last in
            guard now &- last >= interval else { return false }
            last = now
            return true
        }
    }
}

public struct FileIndexBuilder: Sendable {
    public let policy: SafetyPolicy
    public let progress: ScanProgress
    /// Called once per measured top-level root, with its finished node.
    public var onRootMeasured: (@Sendable (FolderNode) -> Void)?
    /// Called a few times a second while the walk runs, with live counters and the in-flight
    /// root's accumulated byte total.
    public var onProgress: (@Sendable (ProgressSnapshot) -> Void)?
    /// Called once before the walk starts; a paused gate suspends the step here. Worker threads
    /// cannot await, so mid-walk pauses go through `pauseGate`.
    public var onPause: (@Sendable () async throws -> Void)?
    /// Called when a directory finishes measuring (post-order, so children come first) if it is
    /// interesting enough to render live: shallow enough, or big enough.
    public var onRollup: (@Sendable (FolderNode) -> Void)?
    /// Deepest folder level reported through `onRollup`.
    public var rollupMaxDepth = 2
    /// Folders at or above this size are reported regardless of depth.
    public var rollupMinBytes: Int64 = 32_000_000
    /// Folder levels kept in `FileIndex.trees`; deeper folders only add to their ancestors.
    public var maxDepth = 6
    public var candidateMinSize: Int64 = 1_000_000
    public var collectCandidates = true
    /// Worker count, ncdu's `-t`: 0 = CPU count, 1 = one worker (the serial shape).
    public var threads: Int
    /// Set from outside (task cancellation) to stop the walk and clean up.
    public let cancellation = CancelState()
    /// Synchronous pause source for worker threads; the serial shape uses the same gate.
    public var pauseGate: ScanPauseGate?

    /// Throttles progress snapshots to ~4 Hz across workers.
    private let progressTick = TickGate()

    static let mediaExtensions = SimilarPhotos.extensions.union(SimilarVideos.extensions)
    static let packageExtensions: Set<String> = [
        "app", "photoslibrary", "framework", "bundle", "plugin", "kext", "appex", "xpc", "musiclibrary",
        "tvlibrary", "imovielibrary", "fcpbundle",
    ]
    static let cacheTagSignature = Array("Signature: 8a477f597d28d172789f06886806bc55".utf8)

    public init(policy: SafetyPolicy, progress: ScanProgress = ScanProgress(), threads: Int = 0) {
        self.policy = policy
        self.progress = progress
        self.threads = threads
    }

    /// Metadata-only walk. The async surface waits for the pause gate once, then runs the worker
    /// pool on a detached thread so no cooperative thread is blocked by synchronous IO.
    public func build(roots: [URL]) async throws -> FileIndex {
        try await onPause?()
        let builder = self
        return try await withTaskCancellationHandler(
            operation: {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<FileIndex, Error>) in
                    Thread.detachNewThread {
                        do {
                            continuation.resume(returning: try builder.buildBlocking(roots: roots))
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            },
            onCancel: {
                builder.cancellation.cancel()
            })
    }

    /// Allocated bytes of a file or folder tree (hard links once, dataless files 0), in one pass.
    public static func allocatedSize(of url: URL) async -> Int64 {
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return 0 }
        if (st.st_mode & S_IFMT) == S_IFREG {
            return FileStamp.isDataless(flags: st.st_flags) ? 0 : Int64(st.st_blocks) * 512
        }
        guard (st.st_mode & S_IFMT) == S_IFDIR else { return 0 }
        var builder = FileIndexBuilder(
            policy: SafetyPolicy(home: url.deletingLastPathComponent()), progress: ScanProgress(), threads: 1)
        builder.maxDepth = 0
        builder.collectCandidates = false
        return (try? await builder.build(roots: [url]))?.trees.first?.size ?? 0
    }

    private func buildBlocking(roots: [URL]) throws -> FileIndex {
        if cancellation.isCancelled { throw CancellationError() }
        let count = threads == 0 ? max(1, ProcessInfo.processInfo.activeProcessorCount) : max(1, threads)
        let queue = DirQueue(threads: count)
        let merge = TreeMerge()
        var rootIDs: [Int] = []
        var seed: [DirQueue.OpenDir] = []  // roots beyond the queue capacity: worker 0's stack
        for root in roots {
            let fd = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else {
                merge.recordError(root, Int32(errno))
                continue
            }
            var st = stat()
            guard fstat(fd, &st) == 0 else {
                merge.recordError(root, Int32(errno))
                close(fd)
                continue
            }
            let id = merge.register(url: root, parent: nil, depth: 0)
            rootIDs.append(id)
            let open = DirQueue.OpenDir(
                fd: fd, url: root, depth: 0, excluded: false, device: st.st_dev, node: id,
                root: id, rootURL: root)
            if !queue.push(open) { seed.append(open) }
        }

        if count == 1 {
            Self.workerBody(
                queue: queue, merge: merge, cancel: cancellation, builder: self,
                rootsTotal: roots.count, seed: seed)
        } else {
            let group = DispatchGroup()
            for i in 0..<count {
                group.enter()
                let workerSeed = i == 0 ? seed : []
                let worker = Thread { [self] in
                    Self.workerBody(
                        queue: queue, merge: merge, cancel: cancellation, builder: self,
                        rootsTotal: roots.count, seed: workerSeed)
                    group.leave()
                }
                worker.name = "chet-scan-\(i)"
                worker.stackSize = 512 * 1024  // ncdu's small worker stacks
                worker.start()
            }
            group.wait()
        }
        queue.closeRemaining()  // a cancelled walk may leave dirs unpopped
        if cancellation.isCancelled { throw CancellationError() }

        var index = FileIndex()
        var (trees, pending, candidates, tagged, errors, entriesSeen) = merge.materialize(
            rootIDs: rootIDs, maxDepth: maxDepth)
        index.trees = trees
        index.taggedCaches = tagged
        index.readErrors = errors
        index.entriesSeen = entriesSeen
        index.candidates = candidates.map {
            WalkEntry(url: $0.url, stamp: $0.stamp, reclaimableBytes: $0.reclaimable)
        }
        Self.resolveCandidates(&pending, &index)
        return index
    }

    /// One candidate per (device, inode), at the smallest gate-passing path regardless of
    /// discovery order; sorted so results never depend on walk order.
    private static func resolveCandidates(
        _ pending: inout [InodeKey: [PendingCandidate]], _ index: inout FileIndex
    ) {
        for (_, list) in pending {
            if let best = list.min(by: { $0.url.path < $1.url.path }) {
                index.candidates.append(WalkEntry(url: best.url, stamp: best.stamp, reclaimableBytes: best.reclaimable))
            }
        }
        index.candidates.sort { $0.url.path < $1.url.path }
    }

    /// The stamp and reclaimable size shared by every candidate path, so the two walks cannot
    /// drift.
    static func makeStamp(_ entry: Entry) -> FileStamp {
        FileStamp(
            inode: entry.inode, size: entry.size, modified: entry.modified, links: entry.links,
            isSymlink: false, isRegularFile: true, isDataless: false)
    }

    private static func reclaimableSize(_ entry: Entry, _ fileURL: URL) -> Int64 {
        entry.hasPrivateSize
            ? entry.privateSize
            : (SizeProbe.reclaimableBytes(fileURL) ?? entry.allocatedSize)
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

    /// Reads a folder in batches with `getattrlistbulk`, returning the read errno (0 on success).
    /// With FSOPT_PACK_INVAL_ATTRS every requested attribute is present in each record, so the
    /// layout is fixed: length, returned attribute_set_t (20 bytes), error, name attrreference,
    /// devid, objtype, modtime timespec, flags, fileid, then file attributes linkcount,
    /// totalsize, allocsize, and — with FSOPT_ATTR_CMN_EXTENDED, required for fork attributes —
    /// the privatesize. `stop` lets a worker bail inside a huge directory.
    static func forEachEntry(
        _ fd: Int32, stop: @Sendable () -> Bool = { false }, _ body: (Entry) throws -> Void
    ) throws -> Int32 {
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
            if stop() { return Int32(EINTR) }
            // FSOPT_PACK_INVAL_ATTRS | FSOPT_ATTR_CMN_EXTENDED
            let count = getattrlistbulk(fd, &request, buffer, capacity, 0x8 | 0x20)
            if count <= 0 { return count == 0 ? 0 : Int32(errno) }  // 0: done, -1: unreadable
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

extension FolderNode {
    /// Deterministic child order: results must not depend on walk order (threads or directories).
    static func descendingBySizeThenPath(_ a: FolderNode, _ b: FolderNode) -> Bool {
        a.size == b.size ? a.url.path < b.url.path : a.size > b.size
    }
}

/// (device, inode) identity of a file; Hashable because tuples are not.
private struct InodeKey: Hashable {
    let device: UInt64
    let inode: UInt64
}

/// Candidate buffered until the walk completes so the smallest gate-passing path can win.
private struct PendingCandidate {
    let url: URL
    let stamp: FileStamp
    let reclaimable: Int64
}

/// Shared work queue for the walk: a bounded (16-slot) LIFO of open directory handles, guarded by
/// a mutex + condition (ncdu 2.5's `scan.zig` queue). Workers hand subdirs they cannot keep local
/// to the queue and block when it is empty; the scan is done when every worker is waiting.
final class DirQueue: @unchecked Sendable {
    struct OpenDir: Sendable {
        let fd: Int32
        let url: URL
        let depth: Int
        /// Inherited exclusion (excluded subtree or `.git`/package); the collector flag is the
        /// builder's, applied per directory.
        let excluded: Bool
        let device: dev_t
        let node: Int
        /// Node id and URL of the top-level root this directory belongs to.
        let root: Int
        let rootURL: URL
    }

    static let capacity = 16

    private let cond = NSCondition()
    private var slots: [OpenDir] = []
    private var waiting = 0
    private var done = false
    private let threads: Int

    init(threads: Int) { self.threads = threads }

    /// Hands a directory to another worker; false when the queue is full (caller keeps it local).
    func push(_ dir: OpenDir) -> Bool {
        cond.lock()
        defer { cond.unlock() }
        guard !done, slots.count < Self.capacity else { return false }
        slots.append(dir)
        cond.signal()
        return true
    }

    /// Blocks while the queue is empty; nil when the scan is done or cancelled.
    func pop() -> OpenDir? {
        cond.lock()
        defer { cond.unlock() }
        if done { return nil }
        waiting += 1
        // A cancelled walk broadcasts; waiters must leave instead of waiting again.
        while slots.isEmpty && !done {
            if waiting == threads {
                cond.broadcast()
                return nil
            }
            cond.wait()
        }
        waiting -= 1
        if done { return nil }
        return slots.popLast()
    }

    func cancel() {
        cond.lock()
        done = true
        cond.broadcast()
        cond.unlock()
    }

    /// Closes fds of directories never popped (only possible on a cancelled walk).
    func closeRemaining() {
        cond.lock()
        slots.forEach { close($0.fd) }
        slots = []
        cond.unlock()
    }
}

/// Shared accumulation for the walk. One lock, touched once per directory merge and once per
/// subdir registration — never per entry (ncdu's `mem_sink` merge shape). Directory sizes roll
/// into their parent when the directory completes.
private final class TreeMerge: @unchecked Sendable {
    struct DirNode {
        let url: URL
        let parent: Int?
        let depth: Int
        var size: Int64 = 0
        var children: [Int] = []
        var fileLeaves: [(url: URL, size: Int64)] = []
        var tagged = false
        /// Files merged in; a dir is finalizable only once its own data is in.
        var merged = false
        /// Subdirs registered but not yet finalized (their size not yet rolled up).
        var pendingChildren = 0
    }

    struct FileRecord {
        let key: InodeKey
        let allocated: Int64
        let candidate: PendingCandidate?
        /// Big-file display leaf; only materialized when this record's inode is first counted.
        let leaf: (url: URL, size: Int64)?
    }

    struct Snapshot {
        let node: FolderNode
        let depth: Int
        let isRoot: Bool
    }

    struct State {
        var nodes: [Int: DirNode] = [:]
        var nextID = 0
        var counted = Set<InodeKey>()
        var pending = [InodeKey: [PendingCandidate]]()
        /// Single-link candidates cannot collide, so they need no per-inode ledger.
        var candidates: [PendingCandidate] = []
        var finalized = Set<Int>()
        var finalizedRoots = 0
        var errors: [WalkError] = []
        var entriesSeen = 0
    }

    private let state = Mutex<State>(State())

    func register(url: URL, parent: Int?, depth: Int) -> Int {
        state.withLock { s in
            let id = s.nextID
            s.nextID += 1
            s.nodes[id] = DirNode(url: url, parent: parent, depth: depth)
            if let parent {
                s.nodes[parent]?.children.append(id)
                s.nodes[parent]?.pendingChildren += 1
            }
            return id
        }
    }

    func setTagged(_ node: Int) {
        state.withLock { $0.nodes[node]?.tagged = true }
    }

    func recordError(_ url: URL, _ errno: Int32) {
        state.withLock { $0.errors.append(WalkError(url: url, errno: errno)) }
    }

    /// Merges one directory's files and finalizes its size roll-up: a directory is complete when
    /// its own data is merged and every registered subdir has finalized (ncdu's unref/final shape).
    /// Single-link files arrive pre-summed (`plainBytes`/`plainLeaves`/`plainCandidates`): they
    /// cannot collide across workers, so only hardlink records touch the shared counted set.
    /// Returns the bytes that counted (first-seen hardlinks + all single-link files) and the ids
    /// finalized here.
    func mergeFiles(
        node: Int, entries: Int, batch: [FileRecord], plainBytes: Int64,
        plainLeaves: [(url: URL, size: Int64)], plainCandidates: [PendingCandidate]
    ) -> (counted: Int64, finalized: [Int]) {
        state.withLock { s in
            var total = plainBytes
            for leaf in plainLeaves { s.nodes[node]?.fileLeaves.append(leaf) }
            s.candidates.append(contentsOf: plainCandidates)
            for f in batch {
                if s.counted.insert(f.key).inserted {
                    total += f.allocated
                    if let leaf = f.leaf { s.nodes[node]?.fileLeaves.append(leaf) }
                }
                if let c = f.candidate { s.pending[f.key, default: []].append(c) }
            }
            s.nodes[node]?.size += total
            s.nodes[node]?.merged = true
            s.entriesSeen += entries
            var rolled: [Int] = []
            var cursor = node
            while let n = s.nodes[cursor], n.merged, n.pendingChildren == 0, !s.finalized.contains(cursor) {
                s.finalized.insert(cursor)
                rolled.append(cursor)
                guard let p = n.parent else {
                    s.finalizedRoots += 1
                    break
                }
                s.nodes[p]?.size += n.size
                s.nodes[p]?.pendingChildren -= 1
                cursor = p
            }
            return (total, rolled)
        }
    }

    /// Trees for the ids finalized in one merge, with the depth and root flag the callbacks need.
    func snapshots(_ ids: [Int], maxDepth: Int) -> [Snapshot] {
        state.withLock { s in
            ids.compactMap { id in
                guard let n = s.nodes[id] else { return nil }
                return Snapshot(
                    node: Self.folderNode(id, maxDepth: maxDepth, nodes: s.nodes),
                    depth: n.depth, isRoot: n.parent == nil)
            }
        }
    }

    var rootsDone: Int { state.withLock { $0.finalizedRoots } }

    /// Bytes accumulated so far under one root, for the in-flight progress snapshot.
    func size(of id: Int) -> Int64 { state.withLock { $0.nodes[id]?.size ?? 0 } }

    private static func folderNode(_ id: Int, maxDepth: Int, nodes: [Int: DirNode]) -> FolderNode {
        let n = nodes[id]!
        var children: [FolderNode] = []
        if n.depth < maxDepth {
            children = n.children.map { folderNode($0, maxDepth: maxDepth, nodes: nodes) }
            children += n.fileLeaves.map { FolderNode(url: $0.url, size: $0.size, children: []) }
            children.sort(by: FolderNode.descendingBySizeThenPath)
        }
        return FolderNode(url: n.url, size: n.size, children: children)
    }

    func materialize(rootIDs: [Int], maxDepth: Int) -> (
        trees: [FolderNode], pending: [InodeKey: [PendingCandidate]], candidates: [PendingCandidate],
        tagged: [TaggedFolder], errors: [WalkError], entriesSeen: Int
    ) {
        state.withLock { s in
            let tagged = s.nodes.values.filter(\.tagged)
                .map { TaggedFolder(url: $0.url, bytes: $0.size) }
                .sorted { $0.url.path < $1.url.path }
            return (
                rootIDs.map { Self.folderNode($0, maxDepth: maxDepth, nodes: s.nodes) }, s.pending,
                s.candidates, tagged, s.errors.sorted { $0.url.path < $1.url.path }, s.entriesSeen
            )
        }
    }
}

extension FileIndexBuilder {
    fileprivate static func workerBody(
        queue: DirQueue, merge: TreeMerge, cancel: CancelState, builder: FileIndexBuilder,
        rootsTotal: Int, seed: [DirQueue.OpenDir]
    ) {
        var stack = seed
        while !cancel.isCancelled, let dir = queue.pop() {
            stack.append(dir)
            while !cancel.isCancelled, let d = stack.popLast() {
                process(
                    d, stack: &stack, queue: queue, merge: merge, cancel: cancel, builder: builder,
                    rootsTotal: rootsTotal)
            }
        }
        for d in stack { close(d.fd) }
        // A cancelled worker exits without draining the queue; wake every peer blocked in pop().
        queue.cancel()
    }

    private static func process(
        _ dir: DirQueue.OpenDir, stack: inout [DirQueue.OpenDir], queue: DirQueue,
        merge: TreeMerge, cancel: CancelState, builder: FileIndexBuilder, rootsTotal: Int
    ) {
        defer { close(dir.fd) }
        builder.progress.enter(dir.url.path)
        // Worker threads cannot await the gate, so they hold their open directory and block here.
        while let gate = builder.pauseGate, gate.isPaused, !cancel.isCancelled {
            usleep(50_000)
        }
        if cancel.isCancelled { return }
        let tagged = !dir.excluded && isCacheDir(dir.fd)
        let noCandidates = dir.excluded || tagged || !builder.collectCandidates
        if tagged { merge.setTagged(dir.node) }
        var batch: [TreeMerge.FileRecord] = []
        var plainBytes: Int64 = 0
        var plainLeaves: [(url: URL, size: Int64)] = []
        var plainCandidates: [PendingCandidate] = []
        var entries = 0
        let bulkErrno =
            (try? Self.forEachEntry(dir.fd, stop: { cancel.isCancelled }) { entry in
                entries += 1
                switch entry.kind {
                case .directory:
                    guard entry.device == dir.device else { return }  // another filesystem
                    let childURL = dir.url.appendingPathComponent(entry.name, isDirectory: true)
                    let childFD = openat(dir.fd, entry.name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                    guard childFD >= 0 else {
                        merge.recordError(childURL, Int32(errno))
                        return
                    }
                    let ext = (entry.name as NSString).pathExtension.lowercased()
                    let childExcluded =
                        noCandidates || entry.name == ".git" || Self.packageExtensions.contains(ext)
                    let childNode = merge.register(url: childURL, parent: dir.node, depth: dir.depth + 1)
                    let open = DirQueue.OpenDir(
                        fd: childFD, url: childURL, depth: dir.depth + 1, excluded: childExcluded,
                        device: dir.device, node: childNode, root: dir.root, rootURL: dir.rootURL)
                    if !queue.push(open) { stack.append(open) }
                case .file:
                    if entry.isDataless { return }
                    let big = entry.size >= builder.candidateMinSize
                    let fileURL = dir.url.appendingPathComponent(entry.name, isDirectory: false)
                    let key = InodeKey(device: UInt64(entry.device), inode: entry.inode)
                    let isHardlink = entry.links > 1
                    let leaf: (url: URL, size: Int64)? =
                        big && dir.depth < builder.maxDepth ? (fileURL, entry.allocatedSize) : nil
                    var candidate: PendingCandidate?
                    if !noCandidates {
                        let ext = (entry.name as NSString).pathExtension.lowercased()
                        if big || Self.mediaExtensions.contains(ext),
                            builder.policy.scanGateAllows(
                                fileURL, isSymlink: false, device: entry.device, parentDevice: dir.device)
                        {
                            candidate = PendingCandidate(
                                url: fileURL, stamp: Self.makeStamp(entry),
                                reclaimable: Self.reclaimableSize(entry, fileURL))
                        }
                    }
                    // Single-link files cannot collide across workers; only hardlinks need the
                    // shared counted set, keeping the per-directory merge cheap.
                    if isHardlink {
                        batch.append(
                            TreeMerge.FileRecord(
                                key: key, allocated: entry.allocatedSize, candidate: candidate, leaf: leaf))
                    } else {
                        plainBytes += entry.allocatedSize
                        if let leaf { plainLeaves.append(leaf) }
                        if let candidate { plainCandidates.append(candidate) }
                    }
                case .other:
                    return
                }
            }) ?? -1
        if cancel.isCancelled { return }
        if bulkErrno != 0 { merge.recordError(dir.url, bulkErrno) }
        let (counted, finalized) = merge.mergeFiles(
            node: dir.node, entries: entries, batch: batch, plainBytes: plainBytes,
            plainLeaves: plainLeaves, plainCandidates: plainCandidates)
        builder.progress.add(files: entries, bytes: counted)
        for snapshot in merge.snapshots(finalized, maxDepth: builder.maxDepth) {
            if snapshot.isRoot { builder.onRootMeasured?(snapshot.node) }
            if snapshot.depth <= builder.rollupMaxDepth || snapshot.node.size >= builder.rollupMinBytes {
                builder.onRollup?(snapshot.node)
            }
        }
        builder.emitProgress(
            folder: dir.url.path, rootsDone: merge.rootsDone, rootsTotal: rootsTotal,
            runningRootURL: dir.rootURL, runningRootBytes: merge.size(of: dir.root))
        if cancel.isCancelled { queue.cancel() }
    }

    /// Emits a progress snapshot at most ~4×/s. Called from worker threads.
    fileprivate func emitProgress(
        folder: String, rootsDone: Int, rootsTotal: Int,
        runningRootURL: URL?, runningRootBytes: Int64
    ) {
        guard let onProgress else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        guard progressTick.take(now: now, interval: 250_000_000) else { return }
        onProgress(
            ProgressSnapshot(
                files: progress.files, bytes: progress.bytes, currentFolder: folder,
                rootsDone: rootsDone, rootsTotal: rootsTotal,
                runningRootURL: runningRootURL, runningRootBytes: runningRootBytes))
    }
}
