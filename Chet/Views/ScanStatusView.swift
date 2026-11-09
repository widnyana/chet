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
                ZStack {
                    Circle()
                        .stroke(Theme.hairline, lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: progressFraction)
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "stop.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.ink)
                }
                .frame(width: 24, height: 24)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .help("Stop the scan")
            .accessibilityLabel("Stop the scan")
            .accessibilityIdentifier("toolbar.scanStop")
        } else {
            Button(model.lastScan == nil ? "Scan" : "Scan again", systemImage: "magnifyingglass") {
                model.scan()
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .help("Find files you can remove (Command-R)")
            .accessibilityLabel("Scan for files you can remove")
            .accessibilityIdentifier("toolbar.scan")
        }
    }

    /// Coarse scan-stage fraction: completed steps over the scan steps.
    private var progressFraction: Double {
        let total = max(model.steps.count, 1)
        return Double(model.steps.filter(\.done).count) / Double(total)
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
