import Foundation
import ChetCore
import SwiftUI

extension ScanModel {
    func isSelected(_ url: URL) -> Binding<Bool> {
        Binding(
            get: { self.selected.contains(url) },
            set: { on in
                if on { self.selected.insert(url) } else { self.selected.remove(url) }
            })
    }

    func isSelected(_ snapshot: LocalSnapshot) -> Binding<Bool> {
        Binding(
            get: { self.selectedSnapshots.contains(snapshot) },
            set: { on in
                if on { self.selectedSnapshots.insert(snapshot) } else { self.selectedSnapshots.remove(snapshot) }
            })
    }

    func setSelected(_ urls: [URL], _ on: Bool) {
        if on { selected.formUnion(urls) } else { selected.subtract(urls) }
    }

    func invertSelection(_ urls: [URL]) {
        for url in urls {
            if selected.contains(url) { selected.remove(url) } else { selected.insert(url) }
        }
    }
}
