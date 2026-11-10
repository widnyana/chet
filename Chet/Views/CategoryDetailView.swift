import AppKit
import ChetCore
import QuickLook
import SwiftUI

struct CategoryDetailView: View {
    @Environment(ScanModel.self) private var model
    let category: CategoryState
    let onClean: () -> Void
    let onBack: () -> Void
    @State private var preview: URL?
    @State private var sort: CategorySort = .size
    @State private var ascending = false

    private var urls: [URL] { category.items.map(\.url) }
    private var categorySelected: [ScanItem] { category.items.filter { model.selected.contains($0.url) } }
    private var isInformational: Bool { category.items.first?.risk == .informational }
    private var section: CategorySection {
        CategoryCopy.section(category.id, risk: category.items.first?.risk)
    }

    private var sortedItems: [ScanItem] {
        let ordered: [ScanItem]
        switch sort {
        case .name:
            ordered = category.items.sorted {
                $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent)
                    == .orderedAscending
            }
        case .size:
            ordered = category.items.sorted { $0.reclaimableBytes < $1.reclaimableBytes }
        case .modified:
            ordered = category.items.sorted { $0.stamp.modified < $1.stamp.modified }
        }
        return ascending ? ordered : ordered.reversed()
    }

    var body: some View {
        if isInformational {
            page(bar: EmptyView())
        } else {
            page(bar: commandBar)
        }
    }

    private func page<Bar: View>(bar: Bar) -> some View {
        PageScreen(
            scrolls: false,
            header: {
                PageHeader(
                    title: CategoryCopy.title(category.id, fallback: category.title),
                    subtitle: riskSentence,
                    metric: category.bytes.formatted(.byteCount(style: .file)),
                    metricLabel: "can be reclaimed"
                )
            },
            content: {
                if category.items.isEmpty {
                    EmptyStateView(
                        title: "No entries in this category",
                        message: "Scan again to look for new items.",
                        actionIsPrimary: false,
                        actionTitle: "Back to Home",
                        action: onBack
                    )
                    .pageHorizontalPadding()
                    Spacer()
                } else {
                    if category.needsFullDiskAccess {
                        StatusLabel(
                            text: "Some folders need Full Disk Access",
                            systemImage: "lock.fill",
                            tone: .amber,
                            help: "Chet could not read some folders in this category."
                        )
                        .pageHorizontalPadding()
                        .padding(.bottom, Spacing.s2)
                    }
                    ListHeaderBar(items: category.items)
                    if let groups = model.groups[category.id] {
                        GroupedItemsView(groups: groups)
                    } else {
                        table
                    }
                }
            },
            bar: { bar }
        )
        .focusedValue(
            \.selectionActions,
            SelectionActions(
                all: { model.setSelected(urls, true) },
                none: { model.setSelected(urls, false) },
                invert: { model.invertSelection(urls) })
        )
    }

    private var riskSentence: String {
        let count = category.items.count == 1 ? "1 item" : "\(category.items.count) items"
        switch section {
        case .safe: return "\(count). Apps rebuild this data."
        case .review: return "\(count). Review each item. Removed items go to the Trash."
        case .informational: return "Protected. Chet never removes this."
        }
    }

    private var commandBar: some View {
        CommandBar(
            metric: categorySelected.reduce(0) { $0 + $1.reclaimableBytes }
                .formatted(.byteCount(style: .file)),
            detail: categorySelected.count == 1
                ? "1 item selected" : "\(categorySelected.count) items selected",
            actionTitle: "Clean",
            actionSystemImage: "trash",
            isEnabled: !categorySelected.isEmpty && !model.isCleaning,
            help: "Review and clean the selected items",
            accessibilityLabel:
                "Clean selected, \(categorySelected.count) items",
            disabledReason: "Select an item to clean.",
            action: {
                model.beginClean(categorySelected)
                onClean()
            })
    }

    private var table: some View {
        ColumnTable(items: sortedItems) {
            header
        } row: { item in
            row(item)
        }
        .quickLookPreview($preview)
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.s3) {
                Color.clear.frame(width: ColumnRegistry.spec(.mark).width)
                sortButton("Name", .name)
                    .frame(maxWidth: .infinity, alignment: .leading)
                sortButton("Size", .size)
                    .frame(width: ColumnRegistry.spec(.size).width, alignment: .trailing)
                sortButton("Modified", .modified)
                    .frame(width: ColumnRegistry.spec(.modified).width, alignment: .trailing)
                Text("Risk")
                    .frame(width: ColumnRegistry.spec(.risk).width, alignment: .trailing)
            }
            .font(Typography.caption)
            .pageHorizontalPadding()
            .padding(.vertical, Spacing.s2)
            Hairline()
        }
    }

    private func sortButton(_ title: String, _ column: CategorySort) -> some View {
        SortColumnButton(
            title: title,
            isActive: sort == column,
            ascending: ascending
        ) {
            if sort == column {
                ascending.toggle()
            } else {
                sort = column
                ascending = column == .name
            }
        }
    }

    private func row(_ item: ScanItem) -> some View {
        let canSelect = model.canSelect(item) && item.risk != .informational
        let selected = canSelect && model.selected.contains(item.url)
        return TableRow(
            isHighlighted: selected,
            content: {
                HStack(spacing: Spacing.s3) {
                    if item.risk == .informational {
                        Color.clear.frame(width: ColumnRegistry.spec(.mark).width)
                    } else {
                        RowCheckbox(
                            isOn: model.isSelected(item.url),
                            label: "Remove \(item.url.lastPathComponent)",
                            width: ColumnRegistry.spec(.mark).width,
                            isEnabled: model.canSelect(item),
                            help: model.canSelect(item)
                                ? "Remove"
                                : "Turn on Administrator cleanup in Settings to remove this")
                    }
                    ItemNameCell(item: item)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    SizeColumn(bytes: item.reclaimableBytes, width: ColumnRegistry.spec(.size).width)
                    Text(item.stamp.modified, format: .relative(presentation: .named))
                        .font(Typography.row)
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                        .help(item.stamp.modified.formatted(date: .long, time: .shortened))
                        .frame(width: ColumnRegistry.spec(.modified).width, alignment: .trailing)
                    riskLabel(item)
                        .frame(width: ColumnRegistry.spec(.risk).width, alignment: .trailing)
                }
                .contextMenu {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([item.url])
                    }
                    Button("Quick Look") { preview = item.url }
                    Button("Copy Path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(item.url.path, forType: .string)
                    }
                }
            })
    }

    @ViewBuilder private func riskLabel(_ item: ScanItem) -> some View {
        if item.risk == .informational {
            StatusLabel(
                text: "Protected",
                systemImage: "shield.lefthalf.filled",
                tone: .red)
        } else if item.risk == .review {
            StatusLabel(
                text: "Review",
                systemImage: "exclamationmark.circle",
                tone: .amber)
        } else {
            Color.clear.frame(height: 1)
        }
    }
}

private enum CategorySort {
    case name, size, modified
}
