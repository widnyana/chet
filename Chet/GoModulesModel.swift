import ChetCore
import Foundation
import Observation

@MainActor
@Observable
final class GoModulesModel {
    var location: GoModules.Location?
    var info: GoModules.Info?
    var isLoading = false
    var isWorking = false
    var loadError: String?
    var message: String?
    var showConfirm = false

    var isAvailable: Bool { location != nil }

    var canRemove: Bool { !isLoading && !isWorking && (info?.bytes ?? 0) > 0 }

    var sizeText: String {
        info.map { $0.bytes.formatted(.byteCount(style: .file)) } ?? "—"
    }

    var subtitle: String {
        if isLoading, info == nil { return "Measuring the module cache…" }
        guard location != nil else { return "Go is not installed." }
        guard let info else { return "Measuring the module cache…" }
        guard info.bytes > 0 else { return "The module cache is empty." }
        let count = info.moduleCount
        return "Module cache · \(sizeText) · \(count) \(count == 1 ? "module" : "modules")"
    }

    func load() {
        guard !isLoading else { return }
        isLoading = true
        loadError = nil
        Task {
            let location = await Task.detached(priority: .utility) {
                GoModules.locate()
            }.value
            var info: GoModules.Info?
            if let location {
                info = await Task.detached(priority: .utility) {
                    GoModules.measure(location)
                }.value
            }
            self.location = location
            self.info = info
            if let info, info.version == "Go" {
                self.loadError = "The Go toolchain did not report a version."
            }
            self.isLoading = false
        }
    }

    func reload() {
        message = nil
        load()
    }

    func remove() {
        guard canRemove, let location else { return }
        let dryRun = DryRun.enabled
        let bytes = info?.bytes ?? 0
        isWorking = true
        showConfirm = false
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                GoModules.clean(location, dryRun: dryRun)
            }.value
            self.isWorking = false
            if !result.ok {
                self.message = result.message
            } else if dryRun {
                self.message = result.out
            } else {
                self.message = "Freed \(bytes.formatted(.byteCount(style: .file)))."
                self.load()
            }
        }
    }
}
