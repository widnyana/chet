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
struct ScanStep: Identifiable {
    let id: String
    let title: String
    var done = false

    static let all = [
        ScanStep(id: "rules", title: "Caches, logs and junk folders"),
        ScanStep(id: "duplicates", title: "Duplicate files"),
        ScanStep(id: "large-files", title: "Large and old files"),
        ScanStep(id: "leftovers", title: "Leftovers of deleted apps"),
        ScanStep(id: "photos", title: "Similar and blurry photos"),
        ScanStep(id: "videos", title: "Similar videos"),
        ScanStep(id: "snapshots", title: "Time Machine snapshots"),
    ]
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
    var steps: [ScanStep] = []
    var lastScan: Date?
    private var scanTask: Task<Void, Never>?

    static let titles: [String: String] = [
        "trash": "Trash", "caches": "User caches", "logs": "Logs and crash reports", "xcode": "Xcode build data",
        "xcode-archives": "Xcode archives", "package-caches": "Package manager caches",
        "browser": "Browser caches", "mail-downloads": "Mail downloads", "installers": "Old installers",
        "ios-backups": "iOS device backups", "duplicates": "Duplicates", "large-files": "Large and old files",
        "leftovers": "App leftovers", "similar-photos": "Similar photos", "blurry-photos": "Blurry photos",
        "similar-videos": "Similar videos", "snapshots": "Time Machine local snapshots",
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
        categories = []
        groups = [:]
        snapshots = []
        selected = []
        selectedSnapshots = []
        report = nil
        isScanning = true
        steps = ScanStep.all
        scanTask = Task {
            for await result in RuleScanner().scanAll() {
                merge(result)
            }
            markDone("rules")
            let home = FileManager.default.homeDirectoryForCurrentUser
            let roots = Self.userRoots(home)
            let media = ["Pictures", "Movies", "Desktop", "Downloads"].map { home.appendingPathComponent($0) }
            async let duplicates = Self.findDuplicates(roots)
            async let large = Self.findLargeFiles(roots)
            async let leftovers = Self.findLeftovers()
            async let photos = Self.findPhotos(media)
            async let videos = Self.findVideos(media)
            async let localSnapshots = Self.findSnapshots()

            add(
                "duplicates",
                groups: await duplicates.map { group in
                    ItemGroup(keeper: group.keeper.url, items: group.duplicates.map { Self.item($0, "duplicates") })
                })
            markDone("duplicates")
            add("large-files", items: await large)
            markDone("large-files")
            add("leftovers", items: await leftovers)
            markDone("leftovers")
            let photoResult = await photos
            add(
                "similar-photos",
                groups: (photoResult?.clusters ?? []).map { cluster in
                    ItemGroup(
                        keeper: cluster.keeper.entry.url,
                        items: cluster.others.map { Self.item($0.entry, "similar-photos") })
                })
            add("blurry-photos", items: (photoResult?.blurry ?? []).map { Self.item($0.entry, "blurry-photos") })
            markDone("photos")
            add(
                "similar-videos",
                groups: await videos.map { cluster in
                    ItemGroup(
                        keeper: cluster.keeper.entry.url,
                        items: cluster.others.map { Self.item($0.entry, "similar-videos") })
                })
            markDone("videos")
            snapshots = await localSnapshots
            markDone("snapshots")
            lastScan = Date()
            if !snapshots.isEmpty {
                categories.append(CategoryState(id: "snapshots", title: Self.titles["snapshots"] ?? "Snapshots"))
            }
            isScanning = false
        }
    }

    func cancel() {
        scanTask?.cancel()
        isScanning = false
    }

    func clean() {
        let items = selectedItems
        let chosenSnapshots = Array(selectedSnapshots)
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
            isCleaning = false
        }
    }

    private func markDone(_ id: String) {
        if let index = steps.firstIndex(where: { $0.id == id }) { steps[index].done = true }
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

    /// Top-level folders of the home folder, without Library and hidden folders.
    nonisolated static func userRoots(_ home: URL) -> [URL] {
        let children = (try? FileManager.default.contentsOfDirectory(at: home, includingPropertiesForKeys: nil)) ?? []
        return children.filter { !$0.lastPathComponent.hasPrefix(".") && $0.lastPathComponent != "Library" }
    }

    @concurrent nonisolated static func findDuplicates(_ roots: [URL]) async -> [DuplicateGroup] {
        (try? DuplicateFinder(policy: SafetyPolicy()).find(in: roots)) ?? []
    }

    @concurrent nonisolated static func findLargeFiles(_ roots: [URL]) async -> [ScanItem] {
        (try? LargeFileScanner(policy: SafetyPolicy()).scan(roots)) ?? []
    }

    @concurrent nonisolated static func findLeftovers() async -> [ScanItem] {
        (try? LeftoverScanner().scan()) ?? []
    }

    @concurrent nonisolated static func findPhotos(_ roots: [URL]) async -> PhotoScanResult? {
        try? SimilarPhotos(policy: SafetyPolicy()).scan(roots)
    }

    @concurrent nonisolated static func findVideos(_ roots: [URL]) async -> [VideoCluster] {
        (try? await SimilarVideos(policy: SafetyPolicy()).scan(roots)) ?? []
    }

    @concurrent nonisolated static func findSnapshots() async -> [LocalSnapshot] {
        (try? Snapshots.list()) ?? []
    }

    @concurrent nonisolated static func runClean(_ items: [ScanItem]) async -> CleanReport {
        var cleaner = Cleaner(policy: SafetyPolicy())
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
