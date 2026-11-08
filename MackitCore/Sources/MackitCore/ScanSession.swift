import Darwin
import Foundation

public enum ScanStep: String, Sendable, CaseIterable {
    case rules, index, largeFiles, duplicates, leftovers, photos, videos, snapshots

    public var title: String {
        switch self {
        case .rules: "Caches, logs and junk folders"
        case .index: "Measuring your folders"
        case .largeFiles: "Large and old files"
        case .duplicates: "Duplicate files"
        case .leftovers: "Leftovers of deleted apps"
        case .photos: "Similar and blurry photos"
        case .videos: "Similar videos"
        case .snapshots: "Time Machine snapshots"
        }
    }
}

public enum ScanEvent: Sendable {
    case started(ScanStep)
    case rootMeasured(FolderNode)
    /// Directory rollup while the walk runs; the disk map merges these into a live home tree.
    case treeUpdate(FolderNode)
    case progress(ProgressSnapshot)
    /// Rules step: one completion per scanned rule, so the UI can name the active category.
    case rulesProgress(done: Int, total: Int, category: String)
    /// Any step: how far through its own units it is, with a label naming the unit.
    case stepActivity(ScanStep, done: Int, total: Int, label: String)
    case rules(CategoryResult)
    case folderTrees([FolderNode])
    case taggedCaches([ScanItem])
    case largeFiles([ScanItem])
    case duplicates([DuplicateGroup])
    case leftovers([ScanItem])
    case photos(PhotoScanResult)
    case videos([VideoCluster])
    case snapshots([LocalSnapshot])
    case finished(ScanStep)
    case done
}

/// One scan of a home folder. Steps run one after another at background IO priority, and the
/// user folders are walked once (metadata only); content is read only for candidates.
public final class ScanSession: Sendable {
    public let home: URL
    public let progress = ScanProgress()
    /// Optional pause control; nil scans never pause.
    public let gate: ScanPauseGate?
    /// Which folders the duplicates step may hash. `.standard` (the default) skips
    /// regenerable build dirs, caches, and temporary places; `.everything` includes them.
    public let scope: DuplicateScope
    let largeFileMinSize: Int64
    /// Rule folder scans running at once.
    let ruleConcurrency = 4

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser, largeFileMinSize: Int64 = 500_000_000,
        gate: ScanPauseGate? = nil, scope: DuplicateScope = .standard
    ) {
        self.home = home
        self.largeFileMinSize = largeFileMinSize
        self.gate = gate
        self.scope = scope
    }

    /// Top-level folders of the home folder, without Library and hidden folders.
    public static func userRoots(_ home: URL) -> [URL] {
        let children = (try? FileManager.default.contentsOfDirectory(at: home, includingPropertiesForKeys: nil)) ?? []
        return children.filter { !$0.lastPathComponent.hasPrefix(".") && $0.lastPathComponent != "Library" }
    }

    /// Runs the scan. Stop it by cancelling the task that reads the stream (or by leaving the loop).
    public func events() -> AsyncStream<ScanEvent> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let task = Task(priority: .utility) {
                await self.run { continuation.yield($0) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func run(_ emit: @escaping @Sendable (ScanEvent) -> Void) async {
        let pause: @Sendable () async -> Void = { try? await self.gate?.wait() }
        let previous = getiopolicy_np(IOPOL_TYPE_DISK, IOPOL_SCOPE_PROCESS)
        setiopolicy_np(IOPOL_TYPE_DISK, IOPOL_SCOPE_PROCESS, IOPOL_THROTTLE)
        defer { setiopolicy_np(IOPOL_TYPE_DISK, IOPOL_SCOPE_PROCESS, previous) }
        let policy = SafetyPolicy(home: home)

        emit(.started(.rules))
        let scanner = RuleScanner(home: home)
        let ruleTotal = scanner.rules.count
        emit(.stepActivity(.rules, done: 0, total: ruleTotal, label: "starting"))
        var rulesDone = 0
        await withTaskGroup(of: CategoryResult?.self) { group in
            var pending = scanner.rules.makeIterator()
            for _ in 0..<ruleConcurrency {
                if let rule = pending.next() { group.addTask { try? await scanner.scan(rule) } }
            }
            for await result in group {
                rulesDone += 1
                if let result { emit(.rules(result)) }
                emit(
                    .stepActivity(
                        .rules, done: rulesDone, total: ruleTotal,
                        label: result?.category ?? "unreadable rule"))
                if !Task.isCancelled, let rule = pending.next() { group.addTask { try? await scanner.scan(rule) } }
            }
        }
        guard !Task.isCancelled else { return }
        emit(.finished(.rules))
        await pause()

        emit(.started(.index))
        emit(.stepActivity(.index, done: 0, total: 0, label: "measuring folders"))
        // The index step is metadata-only and interactive when the disk map is open; the
        // throttle resumes for the hashing-heavy steps that follow.
        setiopolicy_np(IOPOL_TYPE_DISK, IOPOL_SCOPE_PROCESS, IOPOL_IMPORTANT)
        var builder = FileIndexBuilder(policy: policy, progress: progress)
        builder.onRootMeasured = { emit(.rootMeasured($0)) }
        builder.onProgress = { emit(.progress($0)) }
        builder.onRollup = { emit(.treeUpdate($0)) }
        builder.onPause = { await pause() }
        let index = try? await builder.build(roots: Self.userRoots(home))
        setiopolicy_np(IOPOL_TYPE_DISK, IOPOL_SCOPE_PROCESS, IOPOL_THROTTLE)
        guard let index, !Task.isCancelled else { return }
        emit(.folderTrees(index.trees))
        emit(
            .taggedCaches(
                index.taggedCaches.compactMap { tagged in
                    guard policy.isDeletable(tagged.url) == .allowed, let stamp = FileStamp.read(tagged.url) else {
                        return nil
                    }
                    return ScanItem(
                        url: tagged.url, categoryID: "tagged-caches", risk: .safe, mode: .permanent,
                        reclaimableBytes: tagged.bytes, stamp: stamp)
                }))
        emit(.finished(.index))

        await pause()
        emit(.started(.largeFiles))
        emit(.stepActivity(.largeFiles, done: 0, total: 0, label: "large and old files"))
        var large = LargeFileScanner(policy: policy)
        large.minSize = largeFileMinSize
        emit(.largeFiles(large.select(from: index.candidates)))
        emit(.finished(.largeFiles))

        await pause()
        emit(.started(.duplicates))
        emit(.stepActivity(.duplicates, done: 0, total: 0, label: "hashing duplicate candidates"))
        // The scope drops regenerable and temporary folders before any hashing runs.
        let duplicates =
            (try? DuplicateFinder(policy: policy).find(entries: DuplicateScope.filter(index.candidates, scope: scope)))
            ?? []
        guard !Task.isCancelled else { return }
        emit(.duplicates(duplicates))
        emit(.finished(.duplicates))

        await pause()
        emit(.started(.leftovers))
        emit(.stepActivity(.leftovers, done: 0, total: 0, label: "unused app data"))
        let leftovers = (try? LeftoverScanner(home: home).scan()) ?? []
        guard !Task.isCancelled else { return }
        emit(.leftovers(leftovers))
        emit(.finished(.leftovers))

        await pause()
        emit(.started(.photos))
        emit(.stepActivity(.photos, done: 0, total: 0, label: "hashing photos"))
        let photos = try? SimilarPhotos(policy: policy).scan(entries: index.candidates)
        guard !Task.isCancelled else { return }
        if let photos { emit(.photos(photos)) }
        emit(.finished(.photos))

        await pause()
        emit(.started(.videos))
        emit(.stepActivity(.videos, done: 0, total: 0, label: "sampling video frames"))
        let videos = (try? await SimilarVideos(policy: policy).scan(entries: index.candidates)) ?? []
        guard !Task.isCancelled else { return }
        emit(.videos(videos))
        emit(.finished(.videos))

        await pause()
        emit(.started(.snapshots))
        emit(.stepActivity(.snapshots, done: 0, total: 0, label: "listing snapshots"))
        let snapshots = (try? Snapshots.list()) ?? []
        guard !Task.isCancelled else { return }
        emit(.snapshots(snapshots))
        emit(.finished(.snapshots))
        emit(.done)
    }
}
