import MackitCore
import SwiftUI

struct ConfirmSheet: View {
    @Environment(ScanModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let items = model.selectedItems
        let permanent = items.filter { $0.mode == .permanent }.reduce(0) { $0 + $1.reclaimableBytes }
        let trashed = items.filter { $0.mode == .trash }.reduce(0) { $0 + $1.reclaimableBytes }
        VStack(alignment: .leading, spacing: 12) {
            Text("Clean \(items.count) items?").font(.title2.bold())
            Label("\(permanent.formatted(.byteCount(style: .file))) deleted permanently", systemImage: "trash.slash")
            Label("\(trashed.formatted(.byteCount(style: .file))) moved to the Trash", systemImage: "trash")
            if !model.selectedSnapshots.isEmpty {
                Label(
                    "\(model.selectedSnapshots.count) Time Machine local snapshots deleted",
                    systemImage: "clock.arrow.circlepath")
            }
            Text("Each item is checked again right before it is removed. Items that changed since the scan are left alone.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Clean", role: .destructive) {
                    model.clean()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}
