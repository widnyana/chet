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
    case progress(ProgressSnapshot)
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
    let largeFileMinSize: Int64
    /// Rule folder scans running at once.
    let ruleConcurrency = 4

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser, largeFileMinSize: Int64 = 500_000_000
    ) {
        self.home = home
        self.largeFileMinSize = largeFileMinSize
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
        let previous = getiopolicy_np(IOPOL_TYPE_DISK, IOPOL_SCOPE_PROCESS)
        setiopolicy_np(IOPOL_TYPE_DISK, IOPOL_SCOPE_PROCESS, IOPOL_THROTTLE)
        defer { setiopolicy_np(IOPOL_TYPE_DISK, IOPOL_SCOPE_PROCESS, previous) }
        let policy = SafetyPolicy(home: home)

        emit(.started(.rules))
        let scanner = RuleScanner(home: home)
        await withTaskGroup(of: CategoryResult?.self) { group in
            var pending = scanner.rules.makeIterator()
            for _ in 0..<ruleConcurrency {
                if let rule = pending.next() { group.addTask { try? scanner.scan(rule) } }
            }
            for await result in group {
                if let result { emit(.rules(result)) }
                if !Task.isCancelled, let rule = pending.next() { group.addTask { try? scanner.scan(rule) } }
            }
        }
        guard !Task.isCancelled else { return }
        emit(.finished(.rules))

        emit(.started(.index))
        // The index step is metadata-only and interactive when the disk map is open; the
        // throttle resumes for the hashing-heavy steps that follow.
        setiopolicy_np(IOPOL_TYPE_DISK, IOPOL_SCOPE_PROCESS, IOPOL_IMPORTANT)
        var builder = FileIndexBuilder(policy: policy, progress: progress)
        builder.onRootMeasured = { emit(.rootMeasured($0)) }
        builder.onProgress = { emit(.progress($0)) }
        let index = try? builder.build(roots: Self.userRoots(home))
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

        emit(.started(.largeFiles))
        var large = LargeFileScanner(policy: policy)
        large.minSize = largeFileMinSize
        emit(.largeFiles(large.select(from: index.candidates)))
        emit(.finished(.largeFiles))

        emit(.started(.duplicates))
        let duplicates = (try? DuplicateFinder(policy: policy).find(entries: index.candidates)) ?? []
        guard !Task.isCancelled else { return }
        emit(.duplicates(duplicates))
        emit(.finished(.duplicates))

        emit(.started(.leftovers))
        let leftovers = (try? LeftoverScanner(home: home).scan()) ?? []
        guard !Task.isCancelled else { return }
        emit(.leftovers(leftovers))
        emit(.finished(.leftovers))

        emit(.started(.photos))
        let photos = try? SimilarPhotos(policy: policy).scan(entries: index.candidates)
        guard !Task.isCancelled else { return }
        if let photos { emit(.photos(photos)) }
        emit(.finished(.photos))

        emit(.started(.videos))
        let videos = (try? await SimilarVideos(policy: policy).scan(entries: index.candidates)) ?? []
        guard !Task.isCancelled else { return }
        emit(.videos(videos))
        emit(.finished(.videos))

        emit(.started(.snapshots))
        let snapshots = (try? Snapshots.list()) ?? []
        guard !Task.isCancelled else { return }
        emit(.snapshots(snapshots))
        emit(.finished(.snapshots))
        emit(.done)
    }
}
