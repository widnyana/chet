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
    @State private var sortOrder: [KeyPathComparator<ScanItem>] = [
        KeyPathComparator(\.reclaimableBytes, order: .reverse)
    ]

    private var urls: [URL] { category.items.map(\.url) }
    private var categorySelected: [ScanItem] { category.items.filter { model.selected.contains($0.url) } }
    private var allSafe: Bool { category.items.allSatisfy { $0.risk == .safe } }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                title: category.title,
                subtitle: riskSentence,
                metric: category.bytes.formatted(.byteCount(style: .file)),
                metricLabel: category.items.count == 1 ? "1 item" : "\(category.items.count) items"
            )
            .padding(.horizontal, Metrics.widePageMargin)
            .padding(.top, Spacing.s6)
            .padding(.bottom, Spacing.s3)
            ListHeaderBar(items: category.items)
            if let groups = model.groups[category.id] {
                GroupedItemsView(groups: groups)
            } else {
                table
            }
        }
        .background(Theme.paper)
        .focusedValue(
            \.selectionActions,
            SelectionActions(
                all: { model.setSelected(urls, true) },
                none: { model.setSelected(urls, false) },
                invert: { model.invertSelection(urls) })
        )
        .safeAreaInset(edge: .bottom) { commandBar }
        .navigationTitle(category.title)
    }

    private var riskSentence: String {
        if allSafe {
            return "Apps rebuild this data. Removed items are deleted."
        }
        return "Review each item. Removed items go to the Trash."
    }

    private var commandBar: some View {
        CommandBar(
            metric: categorySelected.reduce(0) { $0 + $1.reclaimableBytes }
                .formatted(.byteCount(style: .file)),
            detail: categorySelected.count == 1
                ? "1 item selected" : "\(categorySelected.count) items selected",
            actionTitle: "Clean",
            actionSystemImage: "checkmark",
            isEnabled: !categorySelected.isEmpty && !model.isCleaning,
            help: "Review and clean the selected items",
            action: {
                model.beginClean(categorySelected)
                onClean()
            })
    }

    private var table: some View {
        Table(category.items.sorted(using: sortOrder), selection: $rows, sortOrder: $sortOrder) {
            TableColumn("") { item in
                Toggle("Clean", isOn: model.isSelected(item.url))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .accessibilityLabel("Select \(item.url.lastPathComponent)")
            }
            .width(24)
            TableColumn("Name", value: \.url.lastPathComponent) { item in
                ItemNameCell(item: item)
            }
            TableColumn("Size", value: \.reclaimableBytes) { item in
                Text(item.reclaimableBytes.formatted(.byteCount(style: .file)))
                    .font(Typography.row)
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 70, ideal: 90, max: 120)
            TableColumn("Modified", value: \.stamp.modified) { item in
                Text(item.stamp.modified, format: .relative(presentation: .named))
                    .font(Typography.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .help(item.stamp.modified.formatted(date: .long, time: .shortened))
            }
            .width(min: 90, ideal: 120, max: 160)
            TableColumn("Status") { item in
                if item.risk == .review {
                    StatusLabel(
                        text: "Review",
                        systemImage: "exclamationmark.circle",
                        tone: .amber,
                        help: "Check this item before cleaning. It goes to the Trash.")
                } else {
                    StatusLabel(
                        text: "Safe",
                        systemImage: "checkmark",
                        tone: .neutral,
                        help: "Apps rebuild this data.")
                }
            }
            .width(78)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .contextMenu(forSelectionType: URL.self) { picked in
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting(Array(picked)) }
            Button("Quick Look") { preview = picked.first }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(picked.map(\.path).sorted().joined(separator: "\n"), forType: .string)
            }
            Divider()
            Button("Mark for cleaning") { model.setSelected(Array(picked), true) }
            Button("Unmark") { model.setSelected(Array(picked), false) }
        } primaryAction: { picked in
            NSWorkspace.shared.activateFileViewerSelecting(Array(picked))
        }
        .onKeyPress(.space) {
            preview = rows.first
            return .handled
        }
        .quickLookPreview($preview)
        .background(Theme.paper)
    }
}
