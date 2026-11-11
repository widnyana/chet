import ChetCore
import Observation
import SwiftUI

/// Live disk capacity and Trash size for the sidebar footer. Reads touch the filesystem, so
/// they run off the main actor; the published values stay on it.
@MainActor
@Observable
final class SystemStatusModel {
    var capacity: VolumeCapacity?
    var trashBytes: Int64 = 0
    var isEmptyingTrash = false

    func refresh() {
        Task {
            let capacity = await Task.detached(priority: .utility) { VolumeCapacity.current() }.value
            let trash = await Task.detached(priority: .utility) { TrashBin.size(at: TestEnvironment.paths.trash) }
                .value
            self.capacity = capacity
            self.trashBytes = trash
        }
    }

    func emptyTrash() {
        guard !isEmptyingTrash else { return }
        isEmptyingTrash = true
        Task {
            _ = await Task.detached(priority: .userInitiated) {
                TrashBin.empty(at: TestEnvironment.paths.trash, dryRun: DryRun.enabled)
            }.value
            self.isEmptyingTrash = false
            self.refresh()
        }
    }
}
