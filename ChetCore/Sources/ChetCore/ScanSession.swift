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

/// What a folder-size number measures. `.allocated` is the du-convention basis (blocks on disk,
/// hard links once); blocks shared by APFS clones inside the same folder are counted for each
/// clone, so folders full of clones can overstate what deleting them frees. Per-file
/// `reclaimableBytes` carries the clone-aware number.
public enum SizeBasis: Sendable, Equatable {
    case allocated
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
    case folderTrees([FolderNode], SizeBasis)
    /// Folders the walk could not read; sizes may be incomplete.
    case readErrors([WalkError])
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
    /// Settings opt-in: scan and clean paths outside the home folder.
    public let allowOutsideHome: Bool
    /// Settings list: folders never scanned and never cleaned.
    public let excludedPaths: [String]
    /// Rules the user added in Settings, appended to `Rule.catalog` for the rules step.
    public let extraRules: [Rule]
    /// Settings opt-out: steps the user turned off. `.rules` and `.index` always run, because
    /// the index feeds the disk map and the candidate list every optional step reads.
    public let enabledSteps: Set<ScanStep>
    /// What this scan may read. An empty scope scans everything; categories and roots narrow it.
    public let scanScope: ScanScope
    /// Minimum file size the duplicates step considers.
    public let duplicateMinSize: Int64
    /// Files at least this old count as old in the large-files step.
    public let largeFileOldAge: TimeInterval
    let largeFileMinSize: Int64
    /// Worker count for the disk-usage walk (ncdu's `-t`): 0 = CPU count, 1 = serial shape.
    public let scanThreads: Int
    /// Rule folder scans running at once.
    let ruleConcurrency = 4

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser, largeFileMinSize: Int64 = 500_000_000,
        gate: ScanPauseGate? = nil, scope: DuplicateScope = .standard, scanThreads: Int = 0,
        allowOutsideHome: Bool = false, excludedPaths: [String] = [], extraRules: [Rule] = [],
        enabledSteps: Set<ScanStep> = Set(ScanStep.allCases), duplicateMinSize: Int64 = 1_000_000,
        largeFileOldAge: TimeInterval = 365 * 86_400, scanScope: ScanScope = .everywhere
    ) {
        self.home = home
        self.largeFileMinSize = largeFileMinSize
        self.gate = gate
        self.scope = scope
        self.scanThreads = scanThreads
        self.allowOutsideHome = allowOutsideHome
        self.excludedPaths = excludedPaths
        self.extraRules = extraRules
        self.enabledSteps = enabledSteps
        self.scanScope = scanScope.normalized()
        self.duplicateMinSize = duplicateMinSize
        self.largeFileOldAge = largeFileOldAge
    }

    /// Top-level folders of the home folder, without Library and hidden folders.
    public static func userRoots(_ home: URL) -> [URL] {
        let children = (try? FileManager.default.contentsOfDirectory(at: home, includingPropertiesForKeys: nil)) ?? []
        return children.filter { !$0.lastPathComponent.hasPrefix(".") && $0.lastPathComponent != "Library" }
    }

    /// The folders this scan measures. A scope root outside the home folder is honoured only
    /// with the settings opt-in; otherwise it is skipped, never widened to the whole home.
    static func scanRoots(home: URL, scope: ScanScope, allowOutsideHome: Bool) -> [URL] {
        guard !scope.roots.isEmpty else { return userRoots(home) }
        let homePath = ScanScope.canonicalPath(home.path)
        return scope.roots.compactMap { raw in
            let path = URL(fileURLWithPath: raw).standardizedFileURL.path
            let canonical = ScanScope.canonicalPath(path)
            let inside = canonical == homePath || canonical.hasPrefix(homePath + "/")
            guard inside || allowOutsideHome else { return nil }
            return URL(fileURLWithPath: path)
        }
    }

    /// Rules this scan may run: the selected categories, and the rules rooted inside the
    /// scope folders. A rule outside both is never scanned.
    static func scopedRules(
        _ rules: [Rule], home: URL, scope: ScanScope, allowOutsideHome: Bool
    ) -> [Rule] {
        rules.filter { rule in
            if !scope.categories.isEmpty, !scope.categories.contains(rule.category) { return false }
            guard !scope.roots.isEmpty else { return true }
            let homePath = ScanScope.canonicalPath(home.path)
            return rule.roots.contains { root in
                let url =
                    root.hasPrefix("/") ? URL(fileURLWithPath: root) : home.appendingPathComponent(root)
                let path = ScanScope.canonicalPath(url.path)
                let inside = path == homePath || path.hasPrefix(homePath + "/")
                guard inside || allowOutsideHome else { return false }
                return scope.roots.contains { folder in
                    let scoped = ScanScope.canonicalPath(folder)
                    return path == scoped || path.hasPrefix(scoped + "/")
                        || scoped.hasPrefix(path + "/")
                }
            }
        }
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
        let policy = SafetyPolicy(
            home: home, allowsOutsideHome: allowOutsideHome, excludedPaths: excludedPaths)
        let steps = enabledSteps.filter(scanScope.runs)

        let allRules = Rule.catalog + extraRules
        let scopedRules = Self.scopedRules(
            allRules, home: home, scope: scanScope, allowOutsideHome: allowOutsideHome)

        emit(.started(.rules))
        let scanner = RuleScanner(
            home: home, rules: scopedRules, claimingRules: allRules,
            allowOutsideHome: allowOutsideHome, excludedPaths: excludedPaths)
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

        var index: FileIndex?
        if steps.contains(.index) {
            emit(.started(.index))
            emit(.stepActivity(.index, done: 0, total: 0, label: "measuring folders"))
            // The index step is metadata-only and interactive when the disk map is open; the
            // throttle resumes for the hashing-heavy steps that follow.
            setiopolicy_np(IOPOL_TYPE_DISK, IOPOL_SCOPE_PROCESS, IOPOL_IMPORTANT)
            var builder = FileIndexBuilder(policy: policy, progress: progress, threads: scanThreads)
            builder.onRootMeasured = { emit(.rootMeasured($0)) }
            builder.onProgress = { emit(.progress($0)) }
            builder.onRollup = { emit(.treeUpdate($0)) }
            builder.onPause = { await pause() }
            builder.pauseGate = gate
            index = try? await builder.build(
                roots: Self.scanRoots(
                    home: home, scope: scanScope, allowOutsideHome: allowOutsideHome))
            setiopolicy_np(IOPOL_TYPE_DISK, IOPOL_SCOPE_PROCESS, IOPOL_THROTTLE)
            guard !Task.isCancelled else { return }
            if let built = index {
                emit(.folderTrees(built.trees, built.treeSizeBasis))
                emit(.readErrors(built.readErrors))
                if scanScope.categories.isEmpty || scanScope.categories.contains("tagged-caches") {
                    emit(
                        .taggedCaches(
                            built.taggedCaches.compactMap { tagged in
                                guard policy.isDeletable(tagged.url) == .allowed,
                                    let stamp = FileStamp.read(tagged.url)
                                else {
                                    return nil
                                }
                                return ScanItem(
                                    url: tagged.url, categoryID: "tagged-caches", risk: .safe,
                                    mode: .permanent, reclaimableBytes: tagged.bytes, stamp: stamp)
                            }))
                }
            }
        }
        emit(.finished(.index))

        await pause()
        if steps.contains(.largeFiles), let index {
            emit(.started(.largeFiles))
            emit(.stepActivity(.largeFiles, done: 0, total: 0, label: "large and old files"))
            var large = LargeFileScanner(policy: policy)
            large.minSize = largeFileMinSize
            large.oldAge = largeFileOldAge
            emit(.largeFiles(large.select(from: index.candidates)))
        }
        emit(.finished(.largeFiles))

        await pause()
        if steps.contains(.duplicates), let index {
            emit(.started(.duplicates))
            emit(.stepActivity(.duplicates, done: 0, total: 0, label: "hashing duplicate candidates"))
            // The scope drops regenerable and temporary folders before any hashing runs.
            var finder = DuplicateFinder(policy: policy)
            finder.minSize = duplicateMinSize
            let duplicates =
                (try? finder.find(entries: DuplicateScope.filter(index.candidates, scope: scope))) ?? []
            guard !Task.isCancelled else { return }
            emit(.duplicates(duplicates))
        }
        emit(.finished(.duplicates))

        await pause()
        if steps.contains(.leftovers) {
            emit(.started(.leftovers))
            emit(.stepActivity(.leftovers, done: 0, total: 0, label: "unused app data"))
            let leftovers = (try? LeftoverScanner(home: home, policy: policy).scan()) ?? []
            guard !Task.isCancelled else { return }
            emit(.leftovers(leftovers))
        }
        emit(.finished(.leftovers))

        await pause()
        if steps.contains(.photos), let index {
            emit(.started(.photos))
            emit(.stepActivity(.photos, done: 0, total: 0, label: "hashing photos"))
            let photos = try? SimilarPhotos(policy: policy).scan(entries: index.candidates)
            guard !Task.isCancelled else { return }
            if let photos { emit(.photos(photos)) }
        }
        emit(.finished(.photos))

        await pause()
        if steps.contains(.videos), let index {
            emit(.started(.videos))
            emit(.stepActivity(.videos, done: 0, total: 0, label: "sampling video frames"))
            let videos = (try? await SimilarVideos(policy: policy).scan(entries: index.candidates)) ?? []
            guard !Task.isCancelled else { return }
            emit(.videos(videos))
        }
        emit(.finished(.videos))

        await pause()
        if steps.contains(.snapshots) {
            emit(.started(.snapshots))
            emit(.stepActivity(.snapshots, done: 0, total: 0, label: "listing snapshots"))
            let snapshots = (try? Snapshots.list()) ?? []
            guard !Task.isCancelled else { return }
            emit(.snapshots(snapshots))
        }
        emit(.finished(.snapshots))
        emit(.done)
    }
}
