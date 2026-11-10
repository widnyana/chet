import ChetCore
import Foundation
import Observation

@MainActor
@Observable
final class MiseModel {
    private(set) var detection: Mise.Detection = Mise.detect()
    private(set) var snapshot: Mise.Snapshot?
    private(set) var isLoading = false

    var isAvailable: Bool { detection.available }

    func load() {
        isLoading = true
        let detection = Mise.detect()
        self.detection = detection
        guard detection.available else {
            snapshot = nil
            isLoading = false
            return
        }
        Task {
            let loaded = await Task.detached(priority: .utility) {
                Mise.snapshot(detection)
            }.value
            self.snapshot = loaded
            self.isLoading = false
        }
    }

    func reload() {
        load()
    }
}
