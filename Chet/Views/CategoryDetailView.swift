import AppKit
import ChetCore
import QuickLook
import SwiftUI

struct CategoryDetailView: View {
    @Environment(ScanModel.self) private var model
    let category: CategoryState
    let onClean: () -> Void
    @State private var preview: URL?
    @State private var sortOrder: [KeyPathComparator<ScanItem>] = [
        KeyPathComparator(\.reclaimableBytes, order: .reverse)
    ]

    private var urls: [URL] { category.items.map(\.url) }
    private var categorySelected: [ScanItem] { category.items.filter { model.selected.contains($0.url) } }
    private var isInformational: Bool { category.items.first?.risk == .informational }
    private var section: CategorySection {
        CategoryCopy.section(category.id, risk: category.items.first?.risk)
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                title: CategoryCopy.title(category.id, fallback: category.title),
                subtitle: riskSentence,
                metric: category.bytes.formatted(.byteCount(style: .file)),
                metricLabel: "can be freed"
            )
            .padding(.horizontal, Metrics.widePageMargin)
            .padding(.top, Spacing.s6)
            .padding(.bottom, Spacing.s3)
            if category.items.isEmpty {
                EmptyStateView(
                    title: "Nothing here",
                    message: "This group is empty. Scan again later.",
                    systemImage: "folder")
                .padding(.horizontal, Metrics.widePageMargin)
                Spacer()
            } else {
                ListHeaderBar(items: category.items)
                if let groups = model.groups[category.id] {
                    GroupedItemsView(groups: groups)
                } else {
                    table
                }
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
    }

    private var riskSentence: String {
        let count = category.items.count == 1 ? "1 file" : "\(category.items.count) files"
        switch section {
        case .safe: return "\(count). Apps rebuild these, so they are safe to remove."
        case .review: return "\(count). Check each one before removing."
        case .informational: return "Chet does not remove these files."
        }
    }

    @ViewBuilder private var commandBar: some View {
        if !isInformational {
            CommandBar(
                metric: categorySelected.reduce(0) { $0 + $1.reclaimableBytes }
                    .formatted(.byteCount(style: .file)),
                detail: categorySelected.count == 1
                    ? "1 item selected" : "\(categorySelected.count) items selected",
                actionTitle: "Remove selected",
                actionSystemImage: "trash",
                isEnabled: !categorySelected.isEmpty && !model.isCleaning,
                help: "Review and remove the selected items",
                accessibilityLabel:
                    "Remove selected, \(categorySelected.count) items",
                action: {
                    model.beginClean(categorySelected)
                    onClean()
                })
        }
    }

    private var table: some View {
        Table(category.items.sorted(using: sortOrder), sortOrder: $sortOrder) {
            TableColumn("Remove") { item in
                if item.risk != .informational {
                    Toggle("Remove", isOn: model.isSelected(item.url))
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .accessibilityLabel("Remove \(item.url.lastPathComponent)")
                }
            }
            .width(60)
            TableColumn("Name", value: \.url.lastPathComponent) { item in
                ItemNameCell(item: item)
            }
            TableColumn("Last changed", value: \.stamp.modified) { item in
                Text(item.stamp.modified, format: .relative(presentation: .named))
                    .font(Typography.row)
                    .foregroundStyle(Theme.inkSecondary)
                    .help(item.stamp.modified.formatted(date: .long, time: .shortened))
            }
            .width(min: 110, ideal: 140, max: 180)
            TableColumn("Size", value: \.reclaimableBytes) { item in
                Text(item.reclaimableBytes.formatted(.byteCount(style: .file)))
                    .font(Typography.row)
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(90)
            TableColumn("") { item in
                if item.risk == .informational {
                    StatusLabel(
                        text: "Chet can't remove this",
                        systemImage: "info.circle",
                        tone: .neutral)
                }
            }
            TableColumn("") { item in
                Menu {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([item.url])
                    }
                    Button("Quick Look") { preview = item.url }
                    Button("Copy Path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(item.url.path, forType: .string)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help("More actions")
                .accessibilityLabel("More actions for \(item.url.lastPathComponent)")
            }
            .width(28)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .quickLookPreview($preview)
        .background(Theme.paper)
    }
}
