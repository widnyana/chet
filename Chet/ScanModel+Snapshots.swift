import ChetCore
import Foundation

extension ScanModel {
    /// Reads the local snapshots again without running a scan.
    func reloadSnapshots() async {
        do {
            let found = try await Task.detached(priority: .userInitiated) {
                try Snapshots.list()
            }.value
            snapshots = found
            snapshotErrors = []
        } catch {
            snapshotErrors = [error.localizedDescription]
        }
    }
}
