import ChetCore
import Foundation
import SwiftUI

extension ScanModel {
    /// True when this item may be checked. A root-owned item needs the registered helper with
    /// the dry-run gate off, the same rule the app-remnant rows follow.
    func canSelect(_ item: ScanItem) -> Bool {
        !item.requiresAdmin || HelperService.isAvailable
    }

    /// URL form, for the row bindings and the bulk selectors.
    func canSelect(_ url: URL) -> Bool {
        guard let item = itemsByURL[url] else { return true }
        return canSelect(item)
    }

    func isSelected(_ url: URL) -> Binding<Bool> {
        Binding(
            get: { self.selected.contains(url) },
            set: { on in
                if on {
                    guard self.canSelect(url) else { return }
                    self.select(url)
                } else {
                    self.deselect(url)
                }
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
        let allowed = on ? urls.filter { canSelect($0) } : urls
        for url in allowed { if on { select(url) } else { deselect(url) } }
    }

    func invertSelection(_ urls: [URL]) {
        for url in urls {
            if selected.contains(url) {
                deselect(url)
            } else if canSelect(url) {
                select(url)
            }
        }
    }
}
