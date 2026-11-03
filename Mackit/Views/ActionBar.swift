import MackitCore
import SwiftUI

/// Floating glass bar at the bottom of a category: what is selected, and the Clean button.
struct ActionBar: View {
    @Environment(ScanModel.self) private var model
    let items: [ScanItem]
    let onClean: () -> Void

    var body: some View {
        let count = items.count
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                Text(items.reduce(0) { $0 + $1.reclaimableBytes }.formatted(.byteCount(style: .file)))
                    .font(.headline)
                    .monospacedDigit()
                Text(count == 1 ? "1 item selected" : "\(count) items selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Clean", systemImage: "sparkles", action: onClean)
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(count == 0 || model.isCleaning)
                .keyboardShortcut(.delete, modifiers: .command)
                .help("Review and clean the selected items (Command-Delete)")
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .padding(.bottom, 16)
    }
}
