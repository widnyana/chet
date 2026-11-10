import ChetCore
import SwiftUI

/// Toolbar scan control. Both states are native toolbar buttons; the detailed progress
/// lives in the Overview and the Disk map, so nothing else is needed here.
struct ScanStatusView: View {
    @Environment(ScanModel.self) private var model

    var body: some View {
        // One button for both states, so the toolbar item keeps its identity. Swapping two
        // different buttons rebuilds the toolbar item and can shift the page under it.
        Button {
            model.isScanning ? model.cancel() : model.scan()
        } label: {
            if model.isScanning {
                ScanStopGlyph(isSpinning: !model.isPaused)
            } else {
                Label(model.lastScan == nil ? "Scan" : "Scan again", systemImage: "magnifyingglass")
            }
        }
        .help(model.isScanning ? "Stop the scan" : "Scan for caches, logs, and large files (Command-R)")
        .accessibilityLabel(model.isScanning ? "Stop the scan" : "Scan for caches, logs, and large files")
        .accessibilityIdentifier(model.isScanning ? "toolbar.scanStop" : "toolbar.scan")
    }

    /// Spinning ring around a stop square. Drawn in SwiftUI so it is always a circle:
    /// an AppKit `ProgressView` stretches into an oval inside a toolbar button.
    private struct ScanStopGlyph: View {
        let isSpinning: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var angle = 0.0

        var body: some View {
            ZStack {
                Circle().stroke(Theme.inkSecondary.opacity(0.3), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(angle))
                    // The animation belongs to the arc alone. `withAnimation` would put the
                    // repeating curve on the whole transaction, so the toolbar item's label
                    // swap from `Scan` to this glyph would replay the two positions forever.
                    .animation(rotation, value: angle)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Theme.ink)
                    .frame(width: 7, height: 7)
            }
            .frame(width: Spacing.s4, height: Spacing.s4)
            .accessibilityLabel("Stop the scan")
            .onAppear { spin() }
            .onChange(of: isSpinning) { spin() }
        }

        private var rotation: Animation? {
            isSpinning && !reduceMotion ? .linear(duration: 1).repeatForever(autoreverses: false) : nil
        }

        private func spin() {
            angle = 0
            guard isSpinning, !reduceMotion else { return }
            angle = 360
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
