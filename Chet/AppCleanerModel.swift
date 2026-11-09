import AppKit
import ChetCore
import Foundation
import Observation

/// How the app browser lays out the inventory. Layout only. Both styles read the
/// same model state.
enum AppBrowserStyle: String, CaseIterable, Identifiable {
    case grid, list

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grid: "Grid"
        case .list: "List"
        }
    }

    var systemImage: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .list: "list.bullet"
        }
    }

    static let `default` =
        AppBrowserStyle(
            rawValue: UserDefaults.standard.string(forKey: "appBrowserStyle") ?? "") ?? .list
}

/// One app's result inside a bulk pass. The report is the same per-app report the
/// single-app summary shows, so every rule (revalidation, app-bundle-last, dry run)
/// holds per app.
struct BulkUninstallItem: Identifiable {
    let app: InstalledApp
    let report: UninstallReport

    var id: URL { app.url }
}

struct BulkUninstallReport {
    let items: [BulkUninstallItem]
    let dryRun: Bool

    var trashedBytes: Int64 { items.reduce(0) { $0 + $1.report.trashedBytes } }
    var trashedCount: Int { items.reduce(0) { $0 + $1.report.trashedCount } }
    var removedBytes: Int64 { items.reduce(0) { $0 + $1.report.removedBytes } }
    var removedCount: Int { items.reduce(0) { $0 + $1.report.removedCount } }
    var resultCount: Int { items.reduce(0) { $0 + $1.report.results.count } }
}

/// State for the uninstall destination. The core struct does discovery, matching and removal;
/// this model owns the async lifecycle, the selection, and the report sheet.
@MainActor
@Observable
final class AppCleanerModel {
    var apps: [InstalledApp] = []
    var query = ""
    var isLoadingApps = false

    var selectedAppID: URL?
    var components: [AppComponent] = []
    var selectedComponents: Set<URL> = []
    var appSelected = false
    var appBytes: Int64 = 0

    var isLoadingDetail = false
    var isRunning = false
    var isRemoving = false
    var showConfirm = false
    var showBulkConfirm = false
    var report: UninstallReport?
    var bulkReport: BulkUninstallReport?
    var hasFullDiskAccess = true

    var markedApps: Set<URL> = []
    var appSizes: [URL: Int64] = [:]
    var isMeasuringSizes = false
    /// Spotlight last-used dates, filled lazily like `appSizes`. A present key with a nil
    /// value means Spotlight had no record (shown as "Unknown"); an absent key is still loading.
    var appLastUsed: [URL: Date?] = [:]
    var isBulkRemoving = false
    var bulkProgress: (done: Int, total: Int, current: String?)?
    var style = AppBrowserStyle.default {
        didSet { UserDefaults.standard.set(style.rawValue, forKey: "appBrowserStyle") }
    }

    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var detailTask: Task<Void, Never>?
    private var sizeTask: Task<Void, Never>?
    private var lastUsedTask: Task<Void, Never>?
    private var bulkTask: Task<Void, Never>?
    /// Bumped on every selection change; stale component scans are dropped.
    private var generation = 0

    var selectedApp: InstalledApp? {
        guard let selectedAppID else { return nil }
        return apps.first { $0.url == selectedAppID }
    }

    var filteredApps: [InstalledApp] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return apps }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(text)
                || ($0.bundleID?.localizedCaseInsensitiveContains(text) ?? false)
        }
    }

    var selectedComponentList: [AppComponent] {
        components.filter { selectedComponents.contains($0.url) }
    }

    var selectedBytes: Int64 {
        (appSelected ? appBytes : 0) + selectedComponentList.reduce(0) { $0 + $1.bytes }
    }

    var selectedCount: Int { (appSelected ? 1 : 0) + selectedComponentList.count }

    var relatedBytes: Int64 { components.reduce(0) { $0 + $1.bytes } }

    var canRemove: Bool {
        selectedApp != nil && !isRunning && !isRemoving && !isLoadingDetail && selectedCount > 0
    }

    /// True when this row may be checked. A root-owned remnant needs the registered helper;
    /// the dry-run gate is folded into `HelperService.isAvailable`, so a preview selects nothing
    /// the app cannot remove.
    func canSelect(_ component: AppComponent) -> Bool {
        if component.ownership == .privileged { return HelperService.isAvailable }
        return component.isSelectable
    }

    var selectableComponents: [AppComponent] { components.filter { canSelect($0) } }

    func load() {
        guard !isLoadingApps else { return }
        isLoadingApps = true
        hasFullDiskAccess = FullDiskAccess.status() == .granted
        let worker = makeUninstaller()
        Task {
            let found = await Task.detached(priority: .userInitiated) { worker.installedApps() }.value
            apps = found
            isLoadingApps = false
            startMeasuringSizes()
            startMeasuringLastUsed()
            if let selectedAppID, !found.contains(where: { $0.url == selectedAppID }) {
                clearSelection()
            }
        }
    }

    // MARK: - Inventory facts

    /// Where the app lives, for the grid cell and list row. Discovery knows three
    /// families; anything else shows its parent folder.
    func locationLabel(_ app: InstalledApp) -> String {
        if app.url.path == "/Applications" || app.url.path.hasPrefix("/Applications/") {
            return "Applications"
        }
        if app.url.path.hasPrefix(home.appendingPathComponent("Applications").path) {
            return "User Applications"
        }
        return app.url.deletingLastPathComponent().lastPathComponent
    }

    var markedAppsList: [InstalledApp] { apps.filter { markedApps.contains($0.url) } }

    var markedBytes: Int64 { markedAppsList.reduce(0) { $0 + (appSizes[$1.url] ?? 0) } }

    var markedRunningCount: Int { markedAppsList.filter { isAppRunning($0) }.count }

    var canBulkRemove: Bool { !markedApps.isEmpty && !isBulkRemoving && !isRemoving }

    func toggleMark(_ app: InstalledApp) {
        if markedApps.contains(app.url) {
            markedApps.remove(app.url)
        } else {
            markedApps.insert(app.url)
        }
    }

    func clearMarks() { markedApps.removeAll() }

    /// Sizes arrive live, one app at a time, lowest-cost first (alphabetical). A cell
    /// shows "n/a" until its app's measurement lands. Unreadable apps simply get none.
    private func startMeasuringSizes() {
        sizeTask?.cancel()
        let queue = apps.filter { appSizes[$0.url] == nil }
        isMeasuringSizes = !queue.isEmpty
        guard !queue.isEmpty else { return }
        sizeTask = Task {
            for app in queue {
                guard !Task.isCancelled else { return }
                let bytes = await FileIndexBuilder.allocatedSize(of: app.url)
                guard !Task.isCancelled else { return }
                appSizes[app.url] = bytes
            }
            isMeasuringSizes = false
        }
    }

    /// Last-used dates arrive live like sizes, one app at a time. A cell shows a dim
    /// placeholder until its app resolves; apps with no Spotlight record stay nil ("Unknown").
    private func startMeasuringLastUsed() {
        lastUsedTask?.cancel()
        let queue = apps.filter { appLastUsed[$0.url] == nil }
        guard !queue.isEmpty else { return }
        lastUsedTask = Task {
            for app in queue {
                guard !Task.isCancelled else { return }
                let date = await Task.detached(priority: .utility) {
                    AppUninstaller.lastUsedDate(app.url)
                }.value
                guard !Task.isCancelled else { return }
                appLastUsed[app.url] = .some(date)
            }
        }
    }

    // MARK: - Bulk removal

    func beginBulkRemoval() {
        guard canBulkRemove else { return }
        showBulkConfirm = true
    }

    /// One pass over the marked apps. The dry-run gate is read exactly once here, the
    /// same rule the single-app path follows, and every core call receives it. A
    /// running app is never scanned: the core reports it as skipped(appRunning) from
    /// the plan alone, so the batch never waits on it.
    func removeMarked() {
        guard canBulkRemove, !markedApps.isEmpty else { return }
        let targets = apps.filter { markedApps.contains($0.url) }
        let inventory = apps
        let dryRun = DryRun.enabled
        isBulkRemoving = true
        showBulkConfirm = false
        bulkProgress = (0, targets.count, nil)
        bulkTask?.cancel()
        bulkTask = Task {
            var items: [BulkUninstallItem] = []
            for (index, app) in targets.enumerated() {
                guard !Task.isCancelled else { break }
                bulkProgress = (index, targets.count, app.name)
                let running = isAppRunning(app)
                let others = inventory.filter { $0.url != app.url }
                let components =
                    running
                    ? []
                    : await makeUninstaller().components(for: app, installedApps: inventory)
                guard !Task.isCancelled else { break }
                let plan = UninstallPlan(
                    app: app, components: components.filter(\.defaultSelected),
                    includeApp: app.isWritable && !running, appBytes: appSizes[app.url] ?? 0,
                    otherBundleIDs: Set(others.flatMap(\.allBundleIDs)),
                    otherNames: Set(others.map { $0.name.lowercased() }))
                let report = await makeUninstaller().uninstall(plan, dryRun: dryRun)
                items.append(BulkUninstallItem(app: app, report: report))
                bulkProgress = (index + 1, targets.count, app.name)
            }
            guard !Task.isCancelled else { return }
            isBulkRemoving = false
            bulkProgress = nil
            markedApps.removeAll()
            bulkReport = BulkUninstallReport(items: items, dryRun: dryRun)
            load()
        }
    }

    func select(_ app: InstalledApp?) {
        detailTask?.cancel()
        generation += 1
        let current = generation
        guard let app else {
            clearSelection()
            return
        }
        selectedAppID = app.url
        components = []
        selectedComponents = []
        appBytes = 0
        isLoadingDetail = true
        let running = isAppRunning(app)
        isRunning = running
        appSelected = !running && app.isWritable
        let worker = makeUninstaller()
        let inventory = apps
        detailTask = Task {
            let found = await worker.components(for: app, installedApps: inventory)
            let bytes = await FileIndexBuilder.allocatedSize(of: app.url)
            guard current == generation else { return }
            components = found
            selectedComponents = Set(found.filter(\.defaultSelected).map(\.url))
            appBytes = bytes
            isRunning = isAppRunning(app)
            if isRunning {
                appSelected = false
                selectedComponents.removeAll()
            }
            isLoadingDetail = false
        }
    }

    func clearSelection() {
        detailTask?.cancel()
        generation += 1
        selectedAppID = nil
        components = []
        selectedComponents = []
        appSelected = false
        appBytes = 0
        isLoadingDetail = false
        isRunning = false
    }

    func refreshRunningState() {
        guard let app = selectedApp else { return }
        let running = isAppRunning(app)
        isRunning = running
        if running {
            appSelected = false
            selectedComponents.removeAll()
        }
    }

    func setComponent(_ component: AppComponent, _ selected: Bool) {
        guard canSelect(component) else { return }
        if selected {
            selectedComponents.insert(component.url)
        } else {
            selectedComponents.remove(component.url)
        }
    }

    func selectExact() {
        selectedComponents = Set(components.filter(\.defaultSelected).map(\.url))
    }

    func selectAllSelectable() {
        selectedComponents = Set(selectableComponents.map(\.url))
    }

    func clearComponents() {
        selectedComponents.removeAll()
    }

    func beginRemoval() {
        guard canRemove else { return }
        showConfirm = true
    }

    func remove() {
        guard canRemove, let app = selectedApp else { return }
        let others = apps.filter { $0.url != app.url }
        let plan = UninstallPlan(
            app: app, components: selectedComponentList, includeApp: appSelected, appBytes: appBytes,
            otherBundleIDs: Set(others.flatMap(\.allBundleIDs)),
            otherNames: Set(others.map { $0.name.lowercased() }))
        let worker = makeUninstaller()
        let dryRun = DryRun.enabled
        isRemoving = true
        Task {
            let result = await worker.uninstall(plan, dryRun: dryRun)
            report = result
            isRemoving = false
            showConfirm = false
            clearSelection()
            load()
        }
    }

    func isAppRunning(_ app: InstalledApp) -> Bool {
        app.allBundleIDs.contains {
            !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty
        }
    }

    private func makeUninstaller() -> AppUninstaller {
        AppUninstaller(
            home: home, log: AuditLog(), recorder: FlightRecorder.shared,
            privileged: Self.privilegedRemover())
    }

    /// Root remnants go through the daemon only when it is on and the gate is off. The app
    /// bundle itself is never routed here: `appRevalidation` owns that decision.
    @MainActor
    private static func privilegedRemover() -> (@Sendable (URL, String) -> UninstallOutcome?)? {
        guard HelperService.isAvailable else { return nil }
        return { url, bundleID in
            // Measured before the request; the core reports the row's own scanned size.
            let bytes = FileStamp.read(url)?.size ?? 0
            let reply = HelperService.remove(url, bundleID: bundleID)
            switch reply {
            case "ok": return .removed(bytes)
            case let text where text.hasPrefix("failed:"):
                return .failed(String(text.dropFirst("failed:".count)))
            default: return .skipped(.requiresAdmin)
            }
        }
    }
}
