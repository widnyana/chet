import AppKit
import Foundation
import MackitCore
import Observation

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
    var report: UninstallReport?
    var hasFullDiskAccess = true

    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var detailTask: Task<Void, Never>?
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

    var selectableComponents: [AppComponent] { components.filter(\.isSelectable) }

    func load() {
        guard !isLoadingApps else { return }
        isLoadingApps = true
        hasFullDiskAccess = FullDiskAccess.status() == .granted
        let worker = makeUninstaller()
        Task {
            let found = await Task.detached(priority: .userInitiated) { worker.installedApps() }.value
            apps = found
            isLoadingApps = false
            if let selectedAppID, !found.contains(where: { $0.url == selectedAppID }) {
                clearSelection()
            }
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
        guard component.isSelectable else { return }
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
        AppUninstaller(home: home, log: AuditLog(), recorder: FlightRecorder.shared)
    }
}
