import AppKit
import MackitCore
import QuickLook
import SwiftUI

struct CategoryDetailView: View {
    @Environment(ScanModel.self) private var model
    let category: CategoryState
    let onClean: () -> Void
    @State private var rows = Set<URL>()
    @State private var preview: URL?
    /// Clickable column headers; largest-first is the useful default.
    @State private var sortOrder: [KeyPathComparator<ScanItem>] = [
        KeyPathComparator(\.reclaimableBytes, order: .reverse)
    ]

    private var urls: [URL] { category.items.map(\.url) }
    private var categorySelected: [ScanItem] { category.items.filter { model.selected.contains($0.url) } }
    private var selectedCount: Int { categorySelected.count }
    private var allSafe: Bool { category.items.allSatisfy { $0.risk == .safe } }

    var body: some View {
        VStack(spacing: 0) {
            ListHeaderBar(items: category.items)
            if let groups = model.groups[category.id] {
                GroupedItemsView(groups: groups)
            } else {
                table
            }
        }
        .focusedValue(
            \.selectionActions,
            SelectionActions(
                all: { model.setSelected(urls, true) },
                none: { model.setSelected(urls, false) },
                invert: { model.invertSelection(urls) })
        )
        .safeAreaInset(edge: .bottom) {
            ActionBar(
                items: categorySelected,
                onClean: {
                    model.beginClean(categorySelected)
                    onClean()
                })
        }
        .navigationTitle(category.title)
        .navigationSubtitle(
            "\(category.bytes.formatted(.byteCount(style: .file))) · "
                + (allSafe ? "Apps rebuild this data when needed" : "Check each item. Removed items go to the Trash")
        )
    }

    private var table: some View {
        Table(category.items.sorted(using: sortOrder), selection: $rows, sortOrder: $sortOrder) {
            TableColumn("") { item in
                Toggle("Clean", isOn: model.isSelected(item.url))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            }
            .width(22)
            TableColumn("Name", value: \.url.lastPathComponent) { item in
                ItemNameCell(item: item)
            }
            TableColumn("Size", value: \.reclaimableBytes) { item in
                Text(item.reclaimableBytes.formatted(.byteCount(style: .file)))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 70, ideal: 90, max: 120)
            TableColumn("Modified", value: \.stamp.modified) { item in
                Text(item.stamp.modified, format: .relative(presentation: .named))
                    .foregroundStyle(.secondary)
                    .help(item.stamp.modified.formatted(date: .long, time: .shortened))
            }
            .width(min: 90, ideal: 120, max: 160)
        }
        .alternatingRowBackgrounds(.disabled)
        .contextMenu(forSelectionType: URL.self) { picked in
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting(Array(picked)) }
            Button("Quick Look") { preview = picked.first }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(picked.map(\.path).sorted().joined(separator: "\n"), forType: .string)
            }
            Divider()
            Button("Mark for Cleaning") { model.setSelected(Array(picked), true) }
            Button("Unmark") { model.setSelected(Array(picked), false) }
        } primaryAction: { picked in
            NSWorkspace.shared.activateFileViewerSelecting(Array(picked))
        }
        .onKeyPress(.space) {
            preview = rows.first
            return .handled
        }
        .quickLookPreview($preview)
    }
}
