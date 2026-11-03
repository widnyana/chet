import MackitCore
import SwiftUI

/// Mail/Finder-style list header: tri-state checkbox, counts, and the Select menu.
struct ListHeaderBar: View {
    @Environment(ScanModel.self) private var model
    let items: [ScanItem]

    var body: some View {
        let selected = items.filter { model.selected.contains($0.url) }
        HStack(spacing: 12) {
            Button {
                model.setSelected(items.map(\.url), selected.count != items.count)
            } label: {
                Image(systemName: Self.triState(selected: selected.count, total: items.count))
            }
            .buttonStyle(.plain)
            .help(selected.count == items.count ? "Deselect all" : "Select all")
            Text(
                "\(selected.count) of \(items.count) selected, "
                    + selected.reduce(0) { $0 + $1.reclaimableBytes }.formatted(.byteCount(style: .file))
            )
            .monospacedDigit()
            .foregroundStyle(.secondary)
            Spacer()
            Menu {
                Button("All", systemImage: "checkmark.circle") { model.setSelected(items.map(\.url), true) }
                Button("None", systemImage: "circle") { model.setSelected(items.map(\.url), false) }
                Button("Invert", systemImage: "circle.lefthalf.filled") { model.invertSelection(items.map(\.url)) }
                Divider()
                Button("Safe Items Only", systemImage: "checkmark.seal") {
                    model.setSelected(items.map(\.url), false)
                    model.setSelected(items.filter { $0.risk == .safe }.map(\.url), true)
                }
                Button("Older Than 30 Days", systemImage: "calendar.badge.clock") {
                    let cutoff = Date().addingTimeInterval(-30 * 86_400)
                    model.setSelected(items.map(\.url), false)
                    model.setSelected(items.filter { $0.stamp.modified < cutoff }.map(\.url), true)
                }
                Button("Larger Than 100 MB", systemImage: "arrow.up.forward.square") {
                    model.setSelected(items.map(\.url), false)
                    model.setSelected(items.filter { $0.reclaimableBytes >= 100_000_000 }.map(\.url), true)
                }
            } label: {
                Label("Select", systemImage: "checklist")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.4))
    }

    static func triState(selected: Int, total: Int) -> String {
        if selected == 0 { return "square" }
        return selected == total ? "checkmark.square.fill" : "square.lefthalf.filled"
    }
}
