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

@MainActor
@Observable
final class ScanModel {
    var access = FullDiskAccess.status()
    var skipAccessCheck = false
    var categories: [CategoryState] = []
    var isScanning = false
    /// URLs of the items that will be cleaned. Safe items are preselected, review items never are.
    var selected: Set<URL> = []
    private var scanTask: Task<Void, Never>?

    static let titles: [String: String] = [
        "trash": "Trash", "caches": "User caches", "logs": "Logs and crash reports", "xcode": "Xcode build data",
        "xcode-archives": "Xcode archives", "package-caches": "Package manager caches",
        "browser": "Browser caches", "mail-downloads": "Mail downloads", "installers": "Old installers",
        "ios-backups": "iOS device backups",
    ]

    var selectedBytes: Int64 {
        categories.flatMap(\.items).filter { selected.contains($0.url) }.reduce(0) { $0 + $1.reclaimableBytes }
    }

    func refreshAccess() {
        access = FullDiskAccess.status()
    }

    func scan() {
        scanTask?.cancel()
        categories = []
        selected = []
        isScanning = true
        scanTask = Task {
            for await result in RuleScanner().scanAll() {
                merge(result)
            }
            isScanning = false
        }
    }

    func cancel() {
        scanTask?.cancel()
        isScanning = false
    }

    private func merge(_ result: CategoryResult) {
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
}
