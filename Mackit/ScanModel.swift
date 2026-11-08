import Foundation
import MackitCore
import Observation

/// One sidebar row: every item sharing a category id.
struct CategoryState: Identifiable {
    let id: String
    let title: String
    var items: [ScanItem] = []
    var needsFullDiskAccess = false
    var bytes: Int64 { items.reduce(0) { $0 + $1.reclaimableBytes } }
}

/// One phase of a scan, listed on the overview while it runs.
struct ScanStepState: Identifiable {
    let id: MackitCore.ScanStep
    var done = false
    var title: String { id.title }
    static let all = MackitCore.ScanStep.allCases.map { ScanStepState(id: $0) }
}

/// Items that belong together: one keeper that stays, and copies that may go.
struct ItemGroup: Identifiable {
    var id: URL { keeper }
    let keeper: URL
    let items: [ScanItem]
}

@MainActor
@Observable
final class ScanModel {
    var access = FullDiskAccess.status()
    var skipAccessCheck = false
    var categories: [CategoryState] = []
    /// Category id -> groups, for duplicates and similar media.
    var groups: [String: [ItemGroup]] = [:]
    var snapshots: [LocalSnapshot] = []
    var isScanning = false
    var isCleaning = false
    /// URLs of the items that will be cleaned. Safe items are preselected, review items never are.
    var selected: Set<URL> = []
    var selectedSnapshots: Set<LocalSnapshot> = []
    var report: CleanReport?
    var snapshotErrors: [String] = []
    /// Phases of the current or last scan.
    var steps: [ScanStepState] = []
    /// Folder size trees of the last scan, for the disk map.
    var folderTrees: [FolderNode] = []
    /// Live counters of the running scan.
    var progress: ScanProgress?
    /// Step currently running, while a scan is active.
    var currentStep: MackitCore.ScanStep?
    /// Items staged for the confirm sheet: a category's selection, or all selected items.
    var confirmItems: [ScanItem] = []
    var confirmSnapshots: [LocalSnapshot] = []
    var lastScan: Date?
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
        "ios-backups": "iOS device backups", "duplicates": "Duplicates", "large-files": "Large and old files",
        "leftovers": "App leftovers", "similar-photos": "Similar photos", "blurry-photos": "Blurry photos",
        "similar-videos": "Similar videos", "tagged-caches": "Tagged cache folders",
        "snapshots": "Time Machine local snapshots",
    ]

    /// Selected items, each URL once (a file can show up in more than one category).
    var selectedItems: [ScanItem] {
        var seen = Set<URL>()
        return categories.flatMap(\.items).filter { selected.contains($0.url) && seen.insert($0.url).inserted }
    }

    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.reclaimableBytes } }

    /// Everything found, each file counted once.
    var totalBytes: Int64 {
        var seen = Set<URL>()
        return categories.flatMap(\.items).filter { seen.insert($0.url).inserted }.reduce(0) {
            $0 + $1.reclaimableBytes
        }
    }

    func refreshAccess() {
        access = FullDiskAccess.status()
    }

    func scan() {
        scanTask?.cancel()
        generation += 1
        let gen = generation
        categories = []
        groups = [:]
        snapshots = []
        selected = []
        selectedSnapshots = []
        folderTrees = []
        confirmItems = []
        confirmSnapshots = []
        report = nil
        didFinishScan = false
        isScanning = true
        steps = ScanStepState.all
        let session = ScanSession()
        progress = session.progress
        scanTask = Task {
            for await event in session.events() {
                guard gen == generation else { break }
                FlightRecorder.shared?.record(event)
                apply(event)
            }
            guard gen == generation else { return }
            heartbeat?.cancel()
            FlightRecorder.shared?.flushNow()
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
        isScanning = false
        currentStep = nil
        progress = nil
    }

    /// Stage what the confirm sheet will clean. No argument: all selected items,
    /// or the selected snapshots when no items are selected (snapshots page).
    func beginClean(_ items: [ScanItem]? = nil) {
        confirmItems = items ?? selectedItems
        confirmSnapshots = confirmItems.isEmpty ? Array(selectedSnapshots) : []
    }

    func clean() {
        let items = confirmItems
        let chosenSnapshots = confirmSnapshots
        isCleaning = true
        Task {
            let result = await Self.runClean(items)
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
                categories[index].items.removeAll { gone.contains($0.url) }
            }
            groups = groups.mapValues { list in
                list.map { ItemGroup(keeper: $0.keeper, items: $0.items.filter { !gone.contains($0.url) }) }
                    .filter { !$0.items.isEmpty }
            }
            selected.subtract(gone)
            snapshots.removeAll { deleted.contains($0) }
            selectedSnapshots.subtract(deleted)
            snapshotErrors = errors
            report = result
            confirmItems = []
            confirmSnapshots = []
            isCleaning = false
        }
    }

    private func markDone(_ id: MackitCore.ScanStep) {
        if let index = steps.firstIndex(where: { $0.id == id }) { steps[index].done = true }
    }

    private func apply(_ event: ScanEvent) {
        switch event {
        case .started(let step): currentStep = step
        case .rules(let result): merge(result)
        case .folderTrees(let trees): folderTrees = trees
        case .taggedCaches(let items): add("tagged-caches", items: items)
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
            lastScan = Date()
            if !snapshots.isEmpty {
                categories.append(CategoryState(id: "snapshots", title: Self.titles["snapshots"] ?? "Snapshots"))
            }
        }
    }

    private func merge(_ result: CategoryResult) {
        // Empty categories are noise; keep them only to show that Full Disk Access is missing.
        guard !result.items.isEmpty || result.needsFullDiskAccess else { return }
        if !categories.contains(where: { $0.id == result.category }) {
            categories.append(
                CategoryState(id: result.category, title: Self.titles[result.category] ?? result.category))
        }
        guard let index = categories.firstIndex(where: { $0.id == result.category }) else { return }
        categories[index].items += result.items
        categories[index].needsFullDiskAccess = categories[index].needsFullDiskAccess || result.needsFullDiskAccess
        selected.formUnion(result.items.filter { $0.risk == .safe }.map(\.url))
        categories.sort { $0.bytes > $1.bytes }
    }

    private func add(_ id: String, items: [ScanItem] = [], groups newGroups: [ItemGroup] = []) {
        let all = items + newGroups.flatMap(\.items)
        guard !all.isEmpty else { return }
        categories.append(CategoryState(id: id, title: Self.titles[id] ?? id, items: all))
        if !newGroups.isEmpty { groups[id] = newGroups }
        categories.sort { $0.bytes > $1.bytes }
    }

    nonisolated static func item(_ entry: WalkEntry, _ category: String) -> ScanItem {
        ScanItem(
            url: entry.url, categoryID: category, risk: .review, mode: .trash,
            reclaimableBytes: entry.reclaimableBytes, stamp: entry.stamp)
    }

    @concurrent nonisolated static func runClean(_ items: [ScanItem]) async -> CleanReport {
        var cleaner = Cleaner(policy: SafetyPolicy(), recorder: FlightRecorder.shared)
        cleaner.owner = { $0.ownerBundleID }
        return cleaner.clean(items)
    }

    @concurrent nonisolated static func deleteSnapshot(_ snapshot: LocalSnapshot) async -> String? {
        do {
            try Snapshots.delete(snapshot)
            return nil
        } catch {
            return "\(error)"
        }
    }
}
