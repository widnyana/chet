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

    private var urls: [URL] { category.items.map(\.url) }
    private var selectedCount: Int { category.items.filter { model.selected.contains($0.url) }.count }
    private var allSafe: Bool { category.items.allSatisfy { $0.risk == .safe } }

    var body: some View {
        Group {
            if let groups = model.groups[category.id] {
                GroupedItemsView(groups: groups)
            } else {
                table
            }
        }
        .safeAreaInset(edge: .bottom) {
            ActionBar(onClean: onClean)
        }
        .navigationTitle(category.title)
        .navigationSubtitle(
            "\(category.bytes.formatted(.byteCount(style: .file))) · "
                + (allSafe ? "Apps rebuild this data when needed" : "Check each item. Removed items go to the Trash")
        )
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("Select All") { model.setSelected(urls, true) }
                    Button("Select None") { model.setSelected(urls, false) }
                    Divider()
                    Button("Select Safe Items Only") {
                        model.setSelected(urls, false)
                        model.setSelected(category.items.filter { $0.risk == .safe }.map(\.url), true)
                    }
                } label: {
                    Label("\(selectedCount) of \(category.items.count)", systemImage: "checklist")
                        .monospacedDigit()
                }
                .labelStyle(.titleAndIcon)
                .help("Choose which items to clean")
            }
        }
    }

    private var table: some View {
        Table(category.items, selection: $rows) {
            TableColumn("") { item in
                Toggle("Clean", isOn: model.isSelected(item.url))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            }
            .width(22)
            TableColumn("Name") { item in
                ItemNameCell(item: item)
            }
            TableColumn("Size") { item in
                Text(item.reclaimableBytes.formatted(.byteCount(style: .file)))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 70, ideal: 90, max: 120)
            TableColumn("Modified") { item in
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
