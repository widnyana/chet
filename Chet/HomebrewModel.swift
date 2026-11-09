import ChetCore
import Foundation
import Observation

/// The sortable columns of the Homebrew list. Every column is sortable (repo rule).
enum BrewSort: String, CaseIterable {
    case name, kind, version, size, status
}

/// Installed Homebrew packages, their sizes, and the uninstall and cleanup actions. Homebrew
/// calls shell out, so they run off the main actor; the published values stay on it.
@MainActor
@Observable
final class HomebrewModel {
    var packages: [BrewPackage] = []
    var isLoading = false
    var loadError: String?
    let isAvailable = Homebrew.executable != nil

    var marked: Set<String> = []
    var sort: BrewSort = .size
    var ascending = false

    var isWorking = false
    var isUpdating = false
    var actionResult: String?
    var showUninstallConfirm = false
    var showInstaller = false
    var searchText = ""
    var lastQuery = ""
    var searchResults: [Homebrew.SearchResult] = []
    var isSearching = false
    var hasSearched = false
    var searchMessage: String?
    var selectedToInstall: Set<String> = []
    var tapText = ""
    var installerStatus: String?
    var installerFailed = false

    var sortedPackages: [BrewPackage] {
        let sorted = packages.sorted { first, second in
            switch sort {
            case .name:
                return first.title.localizedStandardCompare(second.title) == .orderedAscending
            case .kind:
                return first.kindLabel == second.kindLabel
                    ? first.title.localizedStandardCompare(second.title) == .orderedAscending
                    : first.kindLabel < second.kindLabel
            case .version:
                return first.version.localizedStandardCompare(second.version) == .orderedAscending
            case .size:
                return first.size < second.size
            case .status:
                return statusRank(first) < statusRank(second)
            }
        }
        return ascending ? sorted : sorted.reversed()
    }

    private func statusRank(_ package: BrewPackage) -> Int {
        if package.outdated { return 0 }
        if package.isUnusedDependency { return 1 }
        if package.pinned { return 2 }
        return 3
    }

    var markedPackages: [BrewPackage] { packages.filter { marked.contains($0.id) } }
    var markedOutdated: [BrewPackage] { markedPackages.filter(\.outdated) }
    var markedBytes: Int64 { markedPackages.reduce(0) { $0 + $1.size } }
    var totalBytes: Int64 { packages.reduce(0) { $0 + $1.size } }
    var canAct: Bool { !isWorking && !isLoading && !isUpdating }
    var canUpgrade: Bool { canAct && !markedOutdated.isEmpty }

    var installTargets: [Homebrew.SearchResult] {
        searchResults.filter { selectedToInstall.contains($0.id) }
    }
    var canSearch: Bool {
        canAct && !isSearching
            && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var canInstall: Bool { canAct && !installTargets.isEmpty }
    var canAddTap: Bool {
        canAct && !tapText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var installedIDs: Set<String> {
        Set(packages.map { ($0.kind == .cask ? "cask:" : "formula:") + $0.name })
    }

    func isInstalled(_ result: Homebrew.SearchResult) -> Bool {
        installedIDs.contains(result.id)
    }

    func setInstallMark(_ result: Homebrew.SearchResult, on: Bool) {
        if on { selectedToInstall.insert(result.id) } else { selectedToInstall.remove(result.id) }
    }

    func setMark(_ package: BrewPackage, on: Bool) {
        if on { marked.insert(package.id) } else { marked.remove(package.id) }
    }

    func clearMarks() { marked.removeAll() }

    func setSort(_ next: BrewSort) {
        if sort == next {
            ascending.toggle()
        } else {
            sort = next
            ascending = next != .size
        }
    }

    func load() {
        guard isAvailable, !isLoading else { return }
        isLoading = true
        loadError = nil
        Task {
            do {
                let loaded = try await Task.detached(priority: .utility) {
                    try Homebrew.installed()
                }.value
                self.packages = loaded
                self.marked = self.marked.intersection(Set(loaded.map(\.id)))
            } catch let error as BrewError {
                self.loadError = error.message
            } catch {
                self.loadError = error.localizedDescription
            }
            self.isLoading = false
        }
    }

    func uninstall(zap: Bool) {
        let targets = markedPackages
        guard canAct, !targets.isEmpty else { return }
        let dryRun = DryRun.enabled
        isWorking = true
        showUninstallConfirm = false
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Homebrew.uninstall(targets, zap: zap, dryRun: dryRun)
            }.value
            self.isWorking = false
            if !result.ok {
                self.actionResult = result.message
            } else if dryRun {
                self.actionResult = result.out
            } else {
                self.actionResult =
                    "Removed \(targets.count) \(targets.count == 1 ? "package" : "packages")."
            }
            self.marked.removeAll()
            if !dryRun { self.load() }
        }
    }

    func cleanup() {
        guard canAct else { return }
        let dryRun = DryRun.enabled
        isWorking = true
        Task {
            let (result, freed) = await Task.detached(priority: .userInitiated) {
                Homebrew.cleanup(dryRun: dryRun)
            }.value
            self.isWorking = false
            if !result.ok {
                self.actionResult = result.message
            } else if dryRun {
                self.actionResult = result.out
            } else {
                self.actionResult =
                    freed.map { "Freed about \($0)." } ?? "Cleaned up. Nothing to free."
            }
            if !dryRun { self.load() }
        }
    }

    func update() {
        guard canAct else { return }
        let dryRun = DryRun.enabled
        isUpdating = true
        Task {
            let result = await Task.detached(priority: .utility) {
                Homebrew.update(dryRun: dryRun)
            }.value
            self.isUpdating = false
            self.actionResult =
                result.ok
                ? (dryRun ? result.out : "Homebrew's catalog is up to date.")
                : result.message
            if result.ok && !dryRun { self.load() }
        }
    }

    func upgrade() {
        let targets = markedOutdated
        guard canAct, !targets.isEmpty else { return }
        let dryRun = DryRun.enabled
        isWorking = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Homebrew.upgrade(targets, dryRun: dryRun)
            }.value
            self.isWorking = false
            self.actionResult =
                result.ok
                ? (dryRun
                    ? result.out
                    : "Upgraded \(targets.count) \(targets.count == 1 ? "package" : "packages").")
                : result.message
            self.marked.removeAll()
            if result.ok && !dryRun { self.load() }
        }
    }

    func openInstaller() {
        installerStatus = nil
        installerFailed = false
        showInstaller = true
    }

    func search() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSearch else { return }
        lastQuery = query
        isSearching = true
        searchMessage = nil
        Task {
            let (results, message) = await Task.detached(priority: .utility) {
                Homebrew.search(query)
            }.value
            self.searchResults = results
            self.searchMessage = message
            self.hasSearched = true
            self.isSearching = false
            self.selectedToInstall.removeAll()
        }
    }

    func install() {
        let targets = installTargets
        guard canAct, !targets.isEmpty else { return }
        let formulae = targets.filter { !$0.isCask }.map(\.name)
        let casks = targets.filter(\.isCask).map(\.name)
        let dryRun = DryRun.enabled
        isWorking = true
        installerStatus = nil
        installerFailed = false
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Homebrew.install(formulae: formulae, casks: casks, dryRun: dryRun)
            }.value
            self.isWorking = false
            if result.ok {
                self.showInstaller = false
                self.selectedToInstall.removeAll()
                self.actionResult =
                    dryRun
                    ? result.out
                    : "Installed \(targets.count) \(targets.count == 1 ? "package" : "packages")."
                if !dryRun { self.load() }
            } else {
                self.installerStatus = result.message
                self.installerFailed = true
            }
        }
    }

    func addTap() {
        let name = tapText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canAddTap else { return }
        let dryRun = DryRun.enabled
        isWorking = true
        installerStatus = nil
        installerFailed = false
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Homebrew.addTap(name, dryRun: dryRun)
            }.value
            self.isWorking = false
            if result.ok {
                self.tapText = ""
                self.installerStatus = dryRun ? result.out : "Added the tap \(name)."
                self.installerFailed = false
            } else {
                self.installerStatus = result.message
                self.installerFailed = true
            }
        }
    }
}
