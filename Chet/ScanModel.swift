import ChetCore
import Foundation
import Observation

/// One sidebar row: every item sharing a category id.
struct CategoryState: Identifiable {
    let id: String
    let title: String
    var items: [ScanItem] = []
    var needsFullDiskAccess = false
    /// Sum of `items`, kept by the writers so every render and sort reads it in O(1).
    var bytes: Int64 = 0
}

/// One phase of a scan, listed on the overview while it runs.
struct ScanStepState: Identifiable {
    let id: ChetCore.ScanStep
    var done = false
    var title: String { id.title }
    static let all = ChetCore.ScanStep.allCases.map { ScanStepState(id: $0) }
}

/// Items that belong together: one keeper that stays, and copies that may go.
struct ItemGroup: Identifiable {
    var id: URL { keeper }
    let keeper: URL
    let items: [ScanItem]
}

/// What the scan is doing right now, for every phase. One value feeds the Disk map
/// panel and the toolbar line so the two cannot disagree.
struct ScanActivity {
    var phase: ChetCore.ScanStep
    var done: Int
    /// Zero when the phase has no useful denominator; the bar is then indeterminate.
    var total: Int
    var label: String
    var trail: [String] = []
    var paused = false
}

@MainActor
@Observable
final class ScanModel {
    var access: FullDiskAccess.Status {
        didSet {
            if access == .granted { accessWasGranted = true }
        }
    }
    private(set) var accessWasGranted: Bool

    init() {
        let status = FullDiskAccess.status()
        access = status
        accessWasGranted = status == .granted
    }

    /// Session-only: the user chose "Continue without Full Disk Access", so this launch
    /// shows the app instead of the onboarding screen. Next launch asks again.
    var accessSkipped = false
    /// How many times the user has been sent to Settings; the second attempt unlocks the
    /// "Chet may be listed twice" hint.
    var grantAttempts = UserDefaults.standard.integer(forKey: "grantAttempts")
    /// Worker count for the disk-usage walk (ncdu's `-t`): 0 = CPU count, 1 = serial shape.
    var scanThreads = UserDefaults.standard.integer(forKey: ScanModel.threadsKey) {
        didSet {
            guard oldValue != scanThreads else { return }
            VerboseLog.event(
                .info, .settings, .settingsChanged, .code(.settingsKey, .settingsKeyScanThreads))
            UserDefaults.standard.set(scanThreads, forKey: ScanModel.threadsKey)
        }
    }
    nonisolated static let threadsKey = "scanThreads"
    /// Duplicates opt-in: when true the duplicates step also hashes caches, project build
    /// dirs, and temporary places. Off by default; the Settings page is the only writer.
    var includeTempInDuplicates = UserDefaults.standard.bool(forKey: "includeTempInDuplicates") {
        didSet {
            guard oldValue != includeTempInDuplicates else { return }
            VerboseLog.event(
                .info, .settings, .settingsChanged, .code(.settingsKey, .settingsKeyIncludeTemp))
            UserDefaults.standard.set(includeTempInDuplicates, forKey: "includeTempInDuplicates")
        }
    }
    /// Outside-home opt-in: scan and clean paths outside the home folder, for machines and
    /// projects kept on another disk. Off by default; the Settings page is the only writer.
    var scanOutsideHome = UserDefaults.standard.bool(forKey: ScanModel.outsideHomeKey) {
        didSet {
            guard oldValue != scanOutsideHome else { return }
            VerboseLog.event(
                .info, .settings, .settingsChanged, .code(.settingsKey, .settingsKeyScanOutsideHome))
            UserDefaults.standard.set(scanOutsideHome, forKey: ScanModel.outsideHomeKey)
        }
    }
    nonisolated static let outsideHomeKey = "scanOutsideHome"
    /// Large-file threshold in MB.
    var largeFileMinSizeMB = UserDefaults.standard.object(forKey: ScanModel.largeFileKey) as? Int ?? 500 {
        didSet {
            guard oldValue != largeFileMinSizeMB else { return }
            VerboseLog.event(
                .info, .settings, .settingsChanged, .code(.settingsKey, .settingsKeyLargeFileMinSize))
            UserDefaults.standard.set(largeFileMinSizeMB, forKey: ScanModel.largeFileKey)
        }
    }
    nonisolated static let largeFileKey = "largeFileMinSizeMB"
    /// Settings list: folders the scan and the cleaner never touch. Stored normalized.
    var excludedPaths = UserDefaults.standard.stringArray(forKey: ScanModel.excludedKey) ?? [] {
        didSet {
            guard oldValue != excludedPaths else { return }
            VerboseLog.event(
                .info, .settings, .settingsChanged, .code(.settingsKey, .settingsKeyExcludedPaths))
            UserDefaults.standard.set(excludedPaths, forKey: ScanModel.excludedKey)
        }
    }
    nonisolated static let excludedKey = "excludedPaths"
    /// Settings list: folders the user added as rules. Stored as JSON in `userRulesKey`.
    var userRules =
        (try? JSONDecoder().decode(
            [UserRule].self, from: UserDefaults.standard.data(forKey: ScanModel.userRulesKey) ?? Data())) ?? []
    {
        didSet {
            guard oldValue != userRules else { return }
            VerboseLog.event(
                .info, .settings, .settingsChanged, .code(.settingsKey, .settingsKeyUserRules))
            if userRules.isEmpty {
                UserDefaults.standard.removeObject(forKey: ScanModel.userRulesKey)
            } else {
                UserDefaults.standard.set(
                    try? JSONEncoder().encode(userRules), forKey: ScanModel.userRulesKey)
            }
        }
    }
    nonisolated static let userRulesKey = "userRules"
    /// Steps the user turned off in Settings. Raw values, so a step added later defaults on.
    var disabledSteps = Set(UserDefaults.standard.stringArray(forKey: ScanModel.disabledStepsKey) ?? []) {
        didSet {
            guard oldValue != disabledSteps else { return }
            UserDefaults.standard.set(disabledSteps.sorted(), forKey: ScanModel.disabledStepsKey)
        }
    }
    nonisolated static let disabledStepsKey = "disabledSteps"
    /// Duplicates: smallest file worth hashing, in MB.
    var duplicateMinSizeMB = UserDefaults.standard.object(forKey: ScanModel.duplicateMinKey) as? Int ?? 1 {
        didSet {
            guard oldValue != duplicateMinSizeMB else { return }
            VerboseLog.event(
                .info, .settings, .settingsChanged, .code(.settingsKey, .settingsKeyDuplicateMinSize))
            UserDefaults.standard.set(duplicateMinSizeMB, forKey: ScanModel.duplicateMinKey)
        }
    }
    nonisolated static let duplicateMinKey = "duplicateMinSizeMB"
    /// Large files: age in days at which a smaller file still counts as old.
    var largeFileOldAgeDays = UserDefaults.standard.object(forKey: ScanModel.oldAgeKey) as? Int ?? 365 {
        didSet {
            guard oldValue != largeFileOldAgeDays else { return }
            VerboseLog.event(
                .info, .settings, .settingsChanged, .code(.settingsKey, .settingsKeyLargeFileMinAge))
            UserDefaults.standard.set(largeFileOldAgeDays, forKey: ScanModel.oldAgeKey)
        }
    }
    nonisolated static let oldAgeKey = "largeFileOldAgeDays"
    /// Minutes one administrator approval lasts. Clamped to the helper's own 1...60 range.
    var helperLifetimeMinutes = UserDefaults.standard.object(forKey: ScanModel.helperLifetimeKey) as? Int ?? 10 {
        didSet {
            let clamped = min(60, max(1, helperLifetimeMinutes))
            guard clamped == helperLifetimeMinutes else {
                helperLifetimeMinutes = clamped
                return
            }
            guard oldValue != helperLifetimeMinutes else { return }
            UserDefaults.standard.set(helperLifetimeMinutes, forKey: ScanModel.helperLifetimeKey)
        }
    }
    nonisolated static let helperLifetimeKey = "helperLifetimeMinutes"
    /// Which categories and folders the next scan reads. Session-only unless the user asked
    /// to remember it.
    var scope = ScanModel.storedScope() {
        didSet {
            VerboseLog.event(
                .info, .settings, .settingsChanged, .code(.settingsKey, .settingsKeyScanScope))
            guard remembersScope else { return }
            Self.storeScope(scope)
        }
    }
    /// The user asked the scope to outlive this launch.
    var remembersScope = UserDefaults.standard.bool(forKey: ScanModel.rememberScopeKey) {
        didSet {
            guard oldValue != remembersScope else { return }
            UserDefaults.standard.set(remembersScope, forKey: ScanModel.rememberScopeKey)
            if remembersScope {
                Self.storeScope(scope)
            } else {
                UserDefaults.standard.removeObject(forKey: ScanModel.scopeKey)
            }
        }
    }
    nonisolated static let scopeKey = "scanScope"
    nonisolated static let rememberScopeKey = "scanScopeRemembered"
    /// The scope the results on screen came from.
    private(set) var resultScope = ScanScope.everywhere

    static func storedScope() -> ScanScope {
        guard UserDefaults.standard.bool(forKey: rememberScopeKey),
            let data = UserDefaults.standard.data(forKey: scopeKey),
            let stored = try? JSONDecoder().decode(ScanScope.self, from: data)
        else { return .everywhere }
        return stored.normalized()
    }

    static func storeScope(_ scope: ScanScope) {
        guard let data = try? JSONEncoder().encode(scope.normalized()) else { return }
        UserDefaults.standard.set(data, forKey: scopeKey)
    }
    var categories: [CategoryState] = []
    private var ledger = ScanLedger(
        totalBytes: Int64(UserDefaults.standard.integer(forKey: ScanModel.lastScanBytesKey)))
    /// First item per URL (a file can sit in several categories), filled by `record` so no read
    /// rebuilds it.
    var itemsByURL: [URL: ScanItem] { ledger.itemsByURL }
    var totalBytes: Int64 { ledger.totalBytes }
    var selectedBytes: Int64 { ledger.selectedBytes }
    /// Category id -> groups, for duplicates and similar media.
    var groups: [String: [ItemGroup]] = [:]
    var snapshots: [LocalSnapshot] = []
    var isScanning = false
    var isCleaning = false
    /// Live per-item progress of the running clean pass.
    var cleanProgress: CleanProgress?
    /// Snapshot deletions in the current clean pass; the progress box names them.
    var cleanSnapshotCount = 0
    /// URLs of the items that will be cleaned. Safe items are preselected, review items never are.
    var selected: Set<URL> { ledger.selected }
    var selectedSnapshots: Set<LocalSnapshot> = []
    var report: CleanReport?
    var snapshotErrors: [String] = []
    /// Phases of the current or last scan.
    var steps: [ScanStepState] = []
    /// Folder size trees of the last scan, for the disk map.
    var folderTrees: [FolderNode] = []
    /// What `folderTrees` measure; see `SizeBasis`.
    var treeSizeBasis: SizeBasis = .allocated
    /// Folders the scan could not read; sizes may be incomplete.
    var readErrors: [WalkError] = []
    /// Live home tree while the index walk runs, merged from directory rollups. The disk map
    /// renders this as a nested treemap that grows into its final shape during the scan.
    var liveTree: FolderNode?
    /// Top-level roots measured so far in the running scan, for the disk map's partial render.
    var partialTrees: [FolderNode] = []
    /// Live copy of the walk's counters while the index step runs.
    var rootsProgress: ProgressSnapshot?
    /// Last sampled folders of the walk, newest first (one per progress tick).
    var recentFolders: [String] = []
    /// Live activity for whichever phase is running.
    var activity: ScanActivity?
    /// Files per second, from the last two progress ticks.
    var rate: Double?
    /// When the running scan started.
    var scanStartedAt: Date?
    /// True while the scan is paused via the gate.
    var isPaused = false { didSet { activity?.paused = isPaused } }
    /// The pause gate of the running scan; nil when idle.
    private var pauseGate: ScanPauseGate?
    /// Live counters of the running scan.
    var progress: ScanProgress?
    /// Step currently running, while a scan is active.
    var currentStep: ChetCore.ScanStep?
    /// Items staged for the confirm sheet: a category's selection, or all selected items.
    var confirmItems: [ScanItem] = []
    var confirmSnapshots: [LocalSnapshot] = []
    var lastScan: Date? = UserDefaults.standard.object(forKey: ScanModel.lastScanKey) as? Date
    /// Bytes the last finished scan measured; kept beside `lastScan` so a relaunch still shows
    /// the last result instead of a zero.
    private(set) var lastScanBytes: Int64 = Int64(
        UserDefaults.standard.integer(forKey: ScanModel.lastScanBytesKey))
    nonisolated static let lastScanKey = "lastScanDate"
    nonisolated static let lastScanBytesKey = "lastScanBytes"
    /// True after a scan ended by finishing, not by Stop.
    var didFinishScan = false
    /// Bumped on every scan start and stop; events from stale sessions are dropped.
    private var generation = 0
    private var scanTask: Task<Void, Never>?
    /// Samples ScanProgress into the flight recorder while a scan runs, so a mid-walk death
    /// names the folder in flight (the index walk emits no per-path events).
    private var heartbeat: Task<Void, Never>?

    static let titles: [String: String] = [
        "trash": "Trash", "caches": "User caches", "logs": "Logs and crash reports", "xcode": "Xcode build data",
        "xcode-archives": "Xcode archives", "package-caches": "Package manager caches",
        "browser": "Browser caches", "mail-downloads": "Mail downloads", "installers": "Old installers",
        "ios-backups": "iOS device backups", "duplicates": "Duplicates", "large-files": "Large files",
        "leftovers": "App leftovers", "similar-photos": "Similar photos", "blurry-photos": "Blurry photos",
        "similar-videos": "Similar videos", "tagged-caches": "Tagged cache folders",
        "snapshots": "Time Machine local snapshots", "dev-garbage": "Project build dirs",
        "nix": "Nix", "user-rules": "Your folders",
        "system-caches": "System caches", "system-logs": "System logs",
    ]

    /// Selected items, each URL once (a file can show up in more than one category).
    var selectedItems: [ScanItem] { selected.compactMap { itemsByURL[$0] } }

    /// Counts an item's bytes once, so a URL in two categories adds to the total a single time.
    private func record(_ item: ScanItem) {
        ledger.record(item)
    }

    func select(_ url: URL) {
        ledger.select(url)
    }

    func deselect(_ url: URL) {
        ledger.deselect(url)
    }

    func refreshAccess() {
        access = FullDiskAccess.status()
        if access == .granted {
            // Access landed: the banner and any stale "attempted" state are done.
            bannerDismissed = true
        }
    }

    /// Records that the user is being sent to grant access, before leaving the app.
    func recordGrantAttempt() {
        AccessAttempt.record()
        grantAttempts += 1
        UserDefaults.standard.set(grantAttempts, forKey: "grantAttempts")
        UserDefaults.standard.synchronize()
    }

    /// True when the app should show the non-blocking access banner: Full Disk Access is
    /// denied and the user moved on with "Continue without Full Disk Access".
    var showsAccessBanner: Bool {
        access == .denied && accessSkipped && !bannerDismissed
    }

    var bannerDismissed = false

    func scan() {
        // A second trigger while the scan is running would restart it and throw away the
        // progress the user is watching, so a running scan is never replaced.
        guard !isScanning else { return }
        scanTask?.cancel()
        generation += 1
        let gen = generation
        categories = []
        groups = [:]
        snapshots = []
        ledger.removeAll()
        selectedSnapshots = []
        folderTrees = []
        readErrors = []
        confirmItems = []
        confirmSnapshots = []
        report = nil
        folderTrees = []
        liveTree = nil
        partialTrees = []
        rootsProgress = nil
        didFinishScan = false
        isScanning = true
        let runningScope = scope.normalized()
        resultScope = runningScope
        let runningSteps = enabledScanSteps.filter(runningScope.runs)
        steps = ScanStepState.all.filter { runningSteps.contains($0.id) }
        VerboseLog.event(
            .info, .scan, .scanStarted,
            .code(.step, .stepScan),
            .flag(.allowOutsideHome, scanOutsideHome),
            .count(.excludedPaths, excludedPaths.count),
            .count(.extraRules, userRules.count),
            .count(.enabledSteps, runningSteps.count),
            .bytes(.largeFileThreshold, Int64(largeFileMinSizeMB) * 1_000_000),
            .count(.threads, scanThreads),
            .bytes(.duplicateSize, Int64(duplicateMinSizeMB) * 1_000_000),
            .count(.oldAgeDays, largeFileOldAgeDays))
        let gate = ScanPauseGate()
        pauseGate = gate
        isPaused = false
        scanStartedAt = Date()
        recentFolders = []
        rate = nil
        let session = ScanSession(
            largeFileMinSize: Int64(largeFileMinSizeMB) * 1_000_000,
            gate: gate, scope: includeTempInDuplicates ? .everything : .standard, scanThreads: scanThreads,
            allowOutsideHome: scanOutsideHome, excludedPaths: excludedPaths,
            extraRules: userRules.map(\.rule),
            enabledSteps: runningSteps, duplicateMinSize: Int64(duplicateMinSizeMB) * 1_000_000,
            largeFileOldAge: TimeInterval(largeFileOldAgeDays) * 86_400, scanScope: runningScope)
        progress = session.progress
        scanTask = Task {
            for await event in session.events() {
                guard gen == generation else { break }
                FlightRecorder.shared?.record(event)
                logScanEvent(event)
                apply(event)
            }
            guard gen == generation else { return }
            heartbeat?.cancel()
            FlightRecorder.shared?.flushNow()
            VerboseLog.flush()
            progress = nil
            currentStep = nil
            isScanning = false
        }
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                guard let self, self.isScanning, let p = self.progress else { continue }
                FlightRecorder.shared?.record(
                    step: self.currentStep?.rawValue ?? "scan",
                    "progress: \(p.files) files, \(p.bytes) bytes, in \(p.currentFolder)")
            }
        }
    }

    func cancel() {
        generation += 1
        scanTask?.cancel()
        heartbeat?.cancel()
        FlightRecorder.shared?.record(step: "scan", "cancelled")
        FlightRecorder.shared?.flushNow()
        VerboseLog.flush()
        pauseGate?.setPaused(false)
        pauseGate = nil
        isPaused = false
        scanStartedAt = nil
        rate = nil
        isScanning = false
        currentStep = nil
        progress = nil
        rootsProgress = nil
        liveTree = nil
        partialTrees = []
        recentFolders = []
        activity = nil
        readErrors = []
    }

    /// Pause or resume the running scan; no-op when idle.
    func togglePause() {
        guard isScanning, let gate = pauseGate else { return }
        let next = !isPaused
        gate.setPaused(next)
        isPaused = next
    }

    /// Stage what the confirm sheet will clean. No argument: all selected items,
    /// or the selected snapshots when no items are selected (snapshots page).
    func beginClean(_ items: [ScanItem]? = nil) {
        report = nil
        cleanProgress = nil
        confirmItems =
            items
            ?? selectedItems.sorted { ($0.reclaimableBytes, $1.url.path) > ($1.reclaimableBytes, $0.url.path) }
        confirmSnapshots = confirmItems.isEmpty ? Array(selectedSnapshots) : []
    }

    func clean() {
        let items = confirmItems
        let chosenSnapshots = confirmSnapshots
        let totalBytes = items.reduce(0) { $0 + max(0, $1.reclaimableBytes) }
        report = nil
        cleanProgress = CleanProgress.preparing(total: items.count, totalBytes: totalBytes)
        cleanSnapshotCount = chosenSnapshots.count
        let started = Date()
        isCleaning = true
        // Read on the main actor: the daemon status is a main-thread fact, and the gate wins.
        let approval = HelperService.isAvailable ? helperLifetimeMinutes : nil
        Task {
            let (stream, continuation) = AsyncStream<CleanProgress>.makeStream(
                bufferingPolicy: .bufferingNewest(1))
            let consumer = Task { @MainActor in
                for await progress in stream {
                    self.cleanProgress = progress
                }
            }
            let result = await Self.runClean(items, helperLifetimeMinutes: approval) { continuation.yield($0) }
            continuation.finish()
            await consumer.value
            var errors: [String] = []
            var deleted = Set<LocalSnapshot>()
            for snapshot in chosenSnapshots {
                if let error = await Self.deleteSnapshot(snapshot) {
                    errors.append("\(snapshot.date): \(error)")
                } else {
                    deleted.insert(snapshot)
                }
            }
            let gone = Set(
                result.results.compactMap { cleaned -> URL? in
                    switch cleaned.outcome {
                    case .removed, .trashed: cleaned.item.url
                    case .skipped, .failed: nil
                    }
                })
            for index in categories.indices {
                var removedBytes: Int64 = 0
                categories[index].items.removeAll { item in
                    guard gone.contains(item.url) else { return false }
                    removedBytes += item.reclaimableBytes
                    return true
                }
                categories[index].bytes -= removedBytes
            }
            groups = groups.mapValues { list in
                list.map { ItemGroup(keeper: $0.keeper, items: $0.items.filter { !gone.contains($0.url) }) }
                    .filter { !$0.items.isEmpty }
            }
            for url in gone { ledger.remove(url) }
            snapshots.removeAll { deleted.contains($0) }
            selectedSnapshots.subtract(deleted)
            snapshotErrors = errors
            // Hold the progress surface briefly so a small clean does not flash
            // past the user and read as the old instant summary.
            let elapsed = Date().timeIntervalSince(started)
            if elapsed < 0.45 {
                try? await Task.sleep(for: .seconds(0.45 - elapsed))
            }
            report = result
            confirmItems = []
            confirmSnapshots = []
            cleanProgress = nil
            cleanSnapshotCount = 0
            isCleaning = false
        }
    }

    private static let home = FileManager.default.homeDirectoryForCurrentUser

    /// Fold a directory rollup into the live home tree (V1: subtree replace by URL). A rollup
    /// whose parent chain isn't measured yet is dropped. Its own parent rollup carries it later.
    private func mergeRollup(_ node: FolderNode) {
        guard node.url != Self.home else {
            liveTree = node
            return
        }
        let home = liveTree ?? FolderNode(url: Self.home, size: 0, children: [])
        if node.url.deletingLastPathComponent() == Self.home, node.children.isEmpty {
            // In-flight root snapshot from the progress tick: replace or append as a child.
            liveTree = home.merging(node)
        } else {
            liveTree = home.inserting(node)
        }
    }

    /// Give the in-flight root a live-growing block from the walk's byte counters (V2),
    /// so the map renders from the first progress tick instead of the first rollup.
    private func growInFlightRoot(_ snap: ProgressSnapshot) {
        guard let url = snap.runningRootURL else { return }
        mergeRollup(FolderNode(url: url, size: snap.runningRootBytes, children: []))
    }

    /// Updates the activity value, appending the label to the trail when it changes.
    private func pushActivity(_ step: ChetCore.ScanStep, done: Int, total: Int, label: String) {
        var next = activity ?? ScanActivity(phase: step, done: done, total: total, label: label)
        next.phase = step
        next.done = done
        next.total = total
        if next.label != label || next.trail.isEmpty {
            next.label = label
            next.trail.insert(label, at: 0)
            if next.trail.count > 6 { next.trail.removeLast(next.trail.count - 6) }
        }
        activity = next
    }

    private func markDone(_ id: ChetCore.ScanStep) {
        if let index = steps.firstIndex(where: { $0.id == id }) { steps[index].done = true }
    }

    private func logScanEvent(_ event: ScanEvent) {
        let step: LogCode
        let done: Int?
        let total: Int?
        switch event {
        case .started(let started):
            step = Self.stepCode(started)
            done = nil
            total = nil
        case .stepActivity(let activityStep, let activityDone, let activityTotal, _):
            step = Self.stepCode(activityStep)
            done = activityDone
            total = activityTotal
        case .taggedCaches:
            step = .stepTaggedCaches
            done = nil
            total = nil
        case .rulesProgress, .rules, .finished, .done, .progress, .rootMeasured, .treeUpdate,
            .folderTrees, .readErrors, .largeFiles, .duplicates, .leftovers, .photos, .videos,
            .snapshots:
            return
        }
        VerboseLog.event(
            .debug, .scan, .scanEvent, .code(.step, step),
            done.map { LogField.count(.done, $0) }, total.map { LogField.count(.total, $0) })
    }

    nonisolated static func stepCode(_ step: ScanStep) -> LogCode {
        switch step {
        case .rules: .stepRules
        case .index: .stepIndex
        case .largeFiles: .stepLargeFiles
        case .duplicates: .stepDuplicates
        case .leftovers: .stepLeftovers
        case .photos: .stepPhotos
        case .videos: .stepVideos
        case .snapshots: .stepSnapshots
        }
    }

    private func apply(_ event: ScanEvent) {
        switch event {
        case .started(let step):
            currentStep = step
            activity = ScanActivity(phase: step, done: 0, total: 0, label: step.title, trail: [])
        case .rulesProgress(let done, let total, let category):
            pushActivity(.rules, done: done, total: total, label: Self.titles[category] ?? category)
        case .stepActivity(let step, let done, let total, let label):
            let human = step == .rules ? (Self.titles[label] ?? label) : label
            pushActivity(step, done: done, total: total, label: human)
        case .rules(let result): merge(result)
        case .folderTrees(let trees, let basis):
            folderTrees = trees
            treeSizeBasis = basis
            liveTree = nil
            partialTrees = []
            rootsProgress = nil
        case .readErrors(let errors): readErrors = errors
        case .treeUpdate(let node): mergeRollup(node)
        case .rootMeasured(let node): partialTrees.append(node)
        case .progress(let snapshot):
            if let previous = rootsProgress, snapshot.files >= previous.files {
                rate = Double(snapshot.files - previous.files)
            }
            if snapshot.currentFolder != rootsProgress?.currentFolder, !snapshot.currentFolder.isEmpty {
                recentFolders.insert(snapshot.currentFolder, at: 0)
                if recentFolders.count > 6 { recentFolders.removeLast(recentFolders.count - 6) }
            }
            rootsProgress = snapshot
            growInFlightRoot(snapshot)
            pushActivity(.index, done: snapshot.rootsDone, total: snapshot.rootsTotal, label: snapshot.currentFolder)
        case .taggedCaches(let items):
            add("tagged-caches", items: TaggedCachePrecedence.keep(items, builds: buildItems))
        case .largeFiles(let items): add("large-files", items: items)
        case .duplicates(let found):
            add(
                "duplicates",
                groups: found.map { group in
                    ItemGroup(keeper: group.keeper.url, items: group.duplicates.map { Self.item($0, "duplicates") })
                })
        case .leftovers(let items): add("leftovers", items: items)
        case .photos(let result):
            add(
                "similar-photos",
                groups: result.clusters.map { cluster in
                    ItemGroup(
                        keeper: cluster.keeper.entry.url,
                        items: cluster.others.map { Self.item($0.entry, "similar-photos") })
                })
            add("blurry-photos", items: result.blurry.map { Self.item($0.entry, "blurry-photos") })
        case .videos(let clusters):
            add(
                "similar-videos",
                groups: clusters.map { cluster in
                    ItemGroup(
                        keeper: cluster.keeper.entry.url,
                        items: cluster.others.map { Self.item($0.entry, "similar-videos") })
                })
        case .snapshots(let found): snapshots = found
        case .finished(let step):
            markDone(step)
        case .done:
            didFinishScan = true
            let finishedAt = Date()
            lastScan = finishedAt
            lastScanBytes = totalBytes
            UserDefaults.standard.set(finishedAt, forKey: Self.lastScanKey)
            UserDefaults.standard.set(Int(totalBytes), forKey: Self.lastScanBytesKey)
            if !snapshots.isEmpty {
                categories.append(CategoryState(id: "snapshots", title: Self.titles["snapshots"] ?? "Snapshots"))
            }
        }
    }

    private static let buildCategories: Set<String> = ["dev-garbage", "terraform-build-dirs"]

    private var buildItems: [ScanItem] {
        categories.filter { Self.buildCategories.contains($0.id) }.flatMap(\.items)
    }

    private func dropTaggedCachesShadowed(by builds: [ScanItem]) {
        guard let index = categories.firstIndex(where: { $0.id == "tagged-caches" }) else { return }
        let kept = TaggedCachePrecedence.keep(categories[index].items, builds: builds)
        guard kept.count != categories[index].items.count else { return }
        let keptURLs = Set(kept.map(\.url))
        for item in categories[index].items where !keptURLs.contains(item.url) { unrecord(item) }
        if kept.isEmpty {
            categories.remove(at: index)
        } else {
            categories[index].items = kept
            categories[index].bytes = kept.reduce(Int64(0)) { $0 + $1.reclaimableBytes }
        }
        for item in builds { record(item) }
    }

    private func unrecord(_ item: ScanItem) {
        guard itemsByURL[item.url] == item else { return }
        ledger.remove(item.url)
    }

    private func merge(_ result: CategoryResult) {
        // A category outside the scope is never shown, even if a rule slipped through.
        guard resultScope.categories.isEmpty || resultScope.categories.contains(result.category)
        else { return }
        // Empty categories are noise; keep them only to show that Full Disk Access is missing.
        guard !result.items.isEmpty || result.needsFullDiskAccess else { return }
        VerboseLog.event(
            .debug, .scan, .scanCategory,
            .code(.category, ruleCategoryCode(result.category)),
            .count(.selected, result.items.count))
        if !categories.contains(where: { $0.id == result.category }) {
            categories.append(
                CategoryState(id: result.category, title: Self.titles[result.category] ?? result.category))
        }
        guard let index = categories.firstIndex(where: { $0.id == result.category }) else { return }
        let itemBytes = result.items.reduce(Int64(0)) { $0 + $1.reclaimableBytes }
        for item in result.items { record(item) }
        categories[index].items += result.items
        categories[index].bytes += itemBytes
        categories[index].needsFullDiskAccess = categories[index].needsFullDiskAccess || result.needsFullDiskAccess
        if Self.buildCategories.contains(result.category) {
            dropTaggedCachesShadowed(by: buildItems)
        }
        for item in result.items { ledger.selectIfSafe(item.url) }
        categories = categories.map { ($0.bytes, $0) }.sorted { $0.0 > $1.0 }.map(\.1)
    }

    private func add(_ id: String, items: [ScanItem] = [], groups newGroups: [ItemGroup] = []) {
        let all = items + newGroups.flatMap(\.items)
        guard !all.isEmpty else { return }
        for item in all { record(item) }
        let bytes = all.reduce(Int64(0)) { $0 + $1.reclaimableBytes }
        categories.append(
            CategoryState(id: id, title: Self.titles[id] ?? id, items: all, bytes: bytes))
        if !newGroups.isEmpty { groups[id] = newGroups }
        categories = categories.map { ($0.bytes, $0) }.sorted { $0.0 > $1.0 }.map(\.1)
    }

    nonisolated static func item(_ entry: WalkEntry, _ category: String) -> ScanItem {
        ScanItem(
            url: entry.url, categoryID: category, risk: .review, mode: .trash,
            reclaimableBytes: entry.reclaimableBytes, stamp: entry.stamp)
    }

    @concurrent nonisolated static func runClean(
        _ items: [ScanItem],
        helperLifetimeMinutes: Int?,
        progress: @escaping @Sendable (CleanProgress) -> Void
    ) async -> CleanReport {
        var cleaner = Cleaner(
            policy: SafetyPolicy(
                allowsOutsideHome: UserDefaults.standard.bool(forKey: outsideHomeKey),
                excludedPaths: UserDefaults.standard.stringArray(forKey: excludedKey) ?? []),
            recorder: FlightRecorder.shared, dryRun: DryRun.enabled)
        cleaner.owner = { $0.ownerBundleID }
        if let minutes = helperLifetimeMinutes {
            let lifetime = TimeInterval(min(60, max(1, minutes)) * 60)
            cleaner.privileged = { item in
                let reply = PrivilegedClient(lifetime: lifetime)
                    .remove(item.url.path, bundleID: "id.web.widnyana.chet")
                switch reply {
                case "ok": return .removed(item.reclaimableBytes)
                case let text where text.hasPrefix("failed:"):
                    return .failed(String(text.dropFirst("failed:".count)))
                default: return .skipped(.policy)
                }
            }
        }
        return cleaner.clean(items, progress: progress)
    }

    /// Steps that will run: everything except the ones switched off. Rules and the folder
    /// index always run; they feed the sidebar and the disk map.
    var enabledScanSteps: Set<ScanStep> {
        Set(ScanStep.allCases.filter { !disabledSteps.contains($0.rawValue) })
    }

    /// The scope in words, for the sheet and the partial-scan notice.
    var scopeSummary: String { Self.summary(for: scope) }

    /// The scope the results on screen came from, in words.
    var resultScopeSummary: String { Self.summary(for: resultScope) }

    static func summary(for scope: ScanScope) -> String {
        let scoped = scope.normalized()
        guard scoped.isPartial else { return "Everything" }
        let categories = scoped.categories.count
        let folders = scoped.roots.count
        switch (categories, folders) {
        case (let count, 0): return count == 1 ? "1 category" : "\(count) categories"
        case (0, let count): return count == 1 ? "1 folder" : "\(count) folders"
        default: return "\(categories) categories in \(folders) folders"
        }
    }

    /// True when the results on screen came from a scope narrower than the whole Mac.
    var isPartialScan: Bool { resultScope.isPartial }

    /// Recovery from any partial scan.
    func scanEverything() {
        scope = .everywhere
        scan()
    }

    func isStepEnabled(_ step: ScanStep) -> Bool {
        !disabledSteps.contains(step.rawValue)
    }

    func setStep(_ step: ScanStep, enabled: Bool) {
        if enabled {
            disabledSteps.remove(step.rawValue)
        } else {
            disabledSteps.insert(step.rawValue)
        }
    }

    /// False when the text is not an absolute or `~` path, or when it is already listed.
    @discardableResult
    func addExcludedPath(_ raw: String) -> Bool {
        guard let path = Self.normalizedPath(raw), !excludedPaths.contains(path) else { return false }
        excludedPaths = (excludedPaths + [path]).sorted()
        return true
    }

    func removeExcludedPath(_ path: String) {
        excludedPaths.removeAll { $0 == path }
    }

    func addUserRule(path: String, keepNames: [String] = []) {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        let keep = Array(Set(keepNames)).sorted()
        if let index = userRules.firstIndex(where: { $0.path == normalized }) {
            userRules[index] = UserRule(id: userRules[index].id, path: normalized, keepNames: keep)
        } else {
            userRules.append(UserRule(path: normalized, keepNames: keep))
        }
    }

    func removeUserRule(_ id: String) {
        userRules.removeAll { $0.id == id }
    }

    /// `~/x` becomes `<home>/x`, `/x` stays absolute. Relative text is rejected: it would
    /// exclude nothing and look like it worked.
    static func normalizedPath(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        if trimmed == "~" { return home }
        if trimmed.hasPrefix("~/") { return home + "/" + trimmed.dropFirst(2) }
        guard trimmed.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: trimmed).standardizedFileURL.path
    }

    @concurrent nonisolated static func deleteSnapshot(_ snapshot: LocalSnapshot) async -> String? {
        do {
            try Snapshots.delete(snapshot, dryRun: DryRun.enabled)
            return nil
        } catch {
            return "\(error)"
        }
    }
}
