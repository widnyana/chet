import ChetCore
import SwiftUI

/// Toolbar scan control. While scanning it is one 24 pt ring with a stop glyph:
/// the ring is the loading indicator, the glyph is the action. The detailed
/// progress lives in the Overview and the Disk map, so nothing else is needed here.
struct ScanStatusView: View {
    @Environment(ScanModel.self) private var model

    var body: some View {
        if model.isScanning {
            Button {
                model.cancel()
            } label: {
                Label("Stop scan", systemImage: "stop.circle")
            }
            .labelStyle(.iconOnly)
            .help("Stop the scan")
            .accessibilityLabel("Stop the scan")
            .accessibilityIdentifier("toolbar.scanStop")
        } else {
            Button {
                model.scan()
            } label: {
                Label(
                    model.lastScan == nil ? "Scan" : "Scan again",
                    systemImage: "magnifyingglass")
            }
            .labelStyle(.iconOnly)
            .help("Scan for caches, logs, and large files (Command-R)")
            .accessibilityLabel("Scan for caches, logs, and large files")
            .accessibilityIdentifier("toolbar.scan")
        }
    }

    /// Which scan step produces a category; nil for pages that are not categories.
    static func step(forCategory id: String) -> ChetCore.ScanStep {
        switch id {
        case "duplicates": .duplicates
        case "large-files": .largeFiles
        case "leftovers": .leftovers
        case "similar-photos", "blurry-photos": .photos
        case "similar-videos": .videos
        case "snapshots": .snapshots
        case "tagged-caches": .index
        default: .rules
        }
    }
}
