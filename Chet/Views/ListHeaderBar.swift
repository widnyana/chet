import ChetCore
import SwiftUI

/// Mail/Finder-style selection header. Flat, with one rule under it.
struct ListHeaderBar: View {
    @Environment(ScanModel.self) private var model
    let items: [ScanItem]

    var body: some View {
        let selected = items.filter { model.selected.contains($0.url) }
        VStack(spacing: 0) {
            HStack(spacing: Spacing.s3) {
                Button {
                    model.setSelected(items.map(\.url), selected.count != items.count)
                } label: {
                    Image(systemName: Self.triState(selected: selected.count, total: items.count))
                        .foregroundStyle(selected.count > 0 ? Theme.accent : Theme.inkSecondary)
                }
                .buttonStyle(.plain)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
                .focusable()
                .focusRing()
                .help(selected.count == items.count ? "Deselect all" : "Select all")
                .accessibilityLabel(selected.count == items.count ? "Deselect all" : "Select all")
                .accessibilityIdentifier("list.selectAll")
                Text(
                    "\(selected.count) of \(items.count) selected · "
                        + selected.reduce(0) { $0 + $1.reclaimableBytes }
                        .formatted(.byteCount(style: .file))
                )
                .font(Typography.row)
                .monospacedDigit()
                .foregroundStyle(Theme.inkSecondary)
                Spacer()
                Menu {
                    Button("All", systemImage: "checkmark.circle") { model.setSelected(items.map(\.url), true) }
                    Button("None", systemImage: "circle") { model.setSelected(items.map(\.url), false) }
                    Button("Invert", systemImage: "arrow.triangle.2.circlepath") {
                        model.invertSelection(items.map(\.url))
                    }
                    Divider()
                    Button("Safe items only", systemImage: "checkmark") {
                        model.setSelected(items.map(\.url), false)
                        model.setSelected(items.filter { $0.risk == .safe }.map(\.url), true)
                    }
                    Button("Older than 30 days", systemImage: "calendar.badge.clock") {
                        let cutoff = Date().addingTimeInterval(-30 * 86_400)
                        model.setSelected(items.map(\.url), false)
                        model.setSelected(items.filter { $0.stamp.modified < cutoff }.map(\.url), true)
                    }
                    Button("Larger than 100 MB", systemImage: "arrow.up.forward.square") {
                        model.setSelected(items.map(\.url), false)
                        model.setSelected(items.filter { $0.reclaimableBytes >= 100_000_000 }.map(\.url), true)
                    }
                } label: {
                    Label("Select", systemImage: "checklist")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .frame(minHeight: Metrics.rowHeight)
            .padding(.horizontal, Spacing.s6)
            .padding(.vertical, Spacing.s2)
            Hairline()
        }
    }

    static func triState(selected: Int, total: Int) -> String {
        if selected == 0 { return "square" }
        return selected == total ? "checkmark.square.fill" : "square.lefthalf.filled"
    }
}
