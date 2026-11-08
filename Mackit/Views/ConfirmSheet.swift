import MackitCore
import SwiftUI

struct ConfirmSheet: View {
    @Environment(ScanModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let items = model.confirmItems
        let rows = Dictionary(grouping: items, by: \.categoryID)
            .map { (id: $0.key, bytes: $0.value.reduce(0) { $0 + $1.reclaimableBytes }) }
            .sorted { $0.bytes > $1.bytes }
        let permanent = items.filter { $0.mode == .permanent }.reduce(0) { $0 + $1.reclaimableBytes }
        let trashed = items.filter { $0.mode == .trash }.reduce(0) { $0 + $1.reclaimableBytes }
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 34))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clean \(model.selectedBytes.formatted(.byteCount(style: .file)))")
                        .font(.title2.bold())
                    Text("\(items.count) items in \(rows.count) categories")
                        .foregroundStyle(.secondary)
                }
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(rows, id: \.id) { row in
                        let style = CategoryStyle.of(row.id)
                        HStack {
                            Image(systemName: style.symbol).foregroundStyle(style.color).frame(width: 22)
                            Text(ScanModel.titles[row.id] ?? row.id)
                            Spacer()
                            Text(row.bytes.formatted(.byteCount(style: .file)))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                    if !model.confirmSnapshots.isEmpty {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath").frame(width: 22)
                            Text("\(model.confirmSnapshots.count) Time Machine local snapshots")
                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 220)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 6) {
                Label(
                    "\(permanent.formatted(.byteCount(style: .file))) deleted now (apps rebuild it)",
                    systemImage: "trash.slash")
                Label("\(trashed.formatted(.byteCount(style: .file))) moved to the Trash", systemImage: "trash")
            }
            .font(.callout)
            Text("Each item is checked again right before removal. Items that changed since the scan are left alone.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if DryRun.enabled {
                Label("DRY RUN: nothing will be deleted", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.large)
                Button("Clean", role: .destructive) {
                    model.clean()
                    dismiss()
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
