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
    var actionResult: String?
    var showUninstallConfirm = false

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
    var markedBytes: Int64 { markedPackages.reduce(0) { $0 + $1.size } }
    var totalBytes: Int64 { packages.reduce(0) { $0 + $1.size } }
    var canAct: Bool { !isWorking && !isLoading }

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
}
