import ChetCore
import SwiftUI

/// Breadcrumb plus the volume line, under the page header.
struct StorageLocationBar: View {
    let pathNodes: [FolderNode]
    let volume: VolumeCapacity?
    let sizeBasis: SizeBasis
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.s2) {
                HStack(spacing: Spacing.s1) {
                    if pathNodes.isEmpty {
                        Text("Home")
                            .font(Typography.caption)
                            .foregroundStyle(Theme.ink)
                    } else {
                        ForEach(Array(pathNodes.enumerated()), id: \.offset) { index, node in
                            if index > 0 {
                                Image(systemName: "chevron.right")
                                    .font(Typography.caption)
                                    .foregroundStyle(Theme.inkTertiary)
                            }
                            if index == pathNodes.count - 1 {
                                Text(title(node, index))
                                    .font(Typography.caption)
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(1)
                                    .accessibilityIdentifier("storage.crumb.current")
                            } else {
                                RowActionButton(
                                    help: "Go to \(title(node, index))",
                                    identifier: "storage.crumb.\(index)",
                                    action: { onSelect(index) },
                                    label: {
                                        Text(title(node, index))
                                            .font(Typography.caption)
                                            .foregroundStyle(Theme.accent)
                                            .lineLimit(1)
                                    })
                            }
                        }
                    }
                }
                Spacer(minLength: Spacing.s3)
                if let volume, volume.total > 0 {
                    Text(
                        "Used \((volume.total - volume.free).formatted(.byteCount(style: .file))) of "
                            + volume.total.formatted(.byteCount(style: .file))
                    )
                    .font(Typography.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.inkSecondary)
                    .accessibilityIdentifier("storage.volume")
                } else {
                    Text("Capacity unavailable")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .accessibilityIdentifier("storage.volume")
                }
                if sizeBasis == .allocated {
                    Text("Size on disk")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.inkTertiary)
                        .help("The space these folders take on the disk.")
                }
            }
            .pageHorizontalPadding()
            .padding(.vertical, Spacing.s2)
            Hairline()
        }
    }

    private func title(_ node: FolderNode, _ index: Int) -> String {
        if index == 0 { return "Home" }
        let name = node.url.lastPathComponent
        return name.isEmpty ? node.url.path : name
    }
}

/// Three headline numbers, flat and separated by hairlines. No card fills.
struct StorageMetricsRow: View {
    let free: Int64?
    let usedShare: Double?
    let cleanable: Int64?
    let largeFilesBytes: Int64?
    let largeFilesCount: Int?
    let didFinishScan: Bool
    /// Both unmeasured metrics offer the same command. While the scan runs, neither can
    /// fire it again: the label states the state and the control is disabled.
    var isScanning = false
    let onScan: () -> Void
    let onOpenFindings: () -> Void
    let onOpenLargeFiles: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            StorageMetric(
                title: "Free space",
                value: free.map { $0.formatted(.byteCount(style: .file)) } ?? "-",
                detail: usedShare.map {
                    "\($0.formatted(.percent.precision(.fractionLength(1)))) used"
                },
                identifier: "storage.metric.free"
            )
            .padding(.trailing, Spacing.s4)
            divider
            StorageMetric(
                title: "Cleanable",
                value: cleanable.map { $0.formatted(.byteCount(style: .file)) } ?? "-",
                actionTitle: isScanning
                    ? "Scanning"
                    : (cleanable == nil ? "Scan for junk" : "View findings"),
                isEnabled: !isScanning,
                action: cleanable == nil ? onScan : onOpenFindings,
                identifier: "storage.metric.cleanable"
            )
            .padding(.horizontal, Spacing.s4)
            divider
            StorageMetric(
                title: "Large files",
                value: largeFilesBytes.map { $0.formatted(.byteCount(style: .file)) } ?? "-",
                detail: largeFilesCount.map { "\($0) files" },
                actionTitle: isScanning
                    ? "Scanning"
                    : (largeFilesBytes == nil
                        ? (didFinishScan ? nil : "Scan to measure") : "View list"),
                isEnabled: !isScanning,
                action: largeFilesBytes == nil
                    ? (didFinishScan ? nil : onScan) : onOpenLargeFiles,
                identifier: "storage.metric.largeFiles"
            )
            .padding(.leading, Spacing.s4)
        }
        .frame(height: 72)
        .pageHorizontalPadding()
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(width: 1, height: 40)
    }
}

struct StorageMetric: View {
    let title: String
    let value: String
    var detail: String?
    var actionTitle: String?
    var isEnabled = true
    var action: (() -> Void)?
    /// Lands on the control (the action button, or the value when there is no action),
    /// never on the container, so selectors stay unambiguous.
    var identifier: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(Typography.caption)
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
            Text(value)
                .font(Typography.metric)
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .modifier(
                    OptionalAccessibilityIdentifier(
                        identifier: actionTitle == nil ? identifier : nil))
            HStack(spacing: Spacing.s1) {
                if let detail {
                    Text(detail)
                        .font(Typography.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                }
                if let actionTitle, let action {
                    QuietActionButton(
                        title: actionTitle, isEnabled: isEnabled, action: action
                    )
                    .modifier(OptionalAccessibilityIdentifier(identifier: identifier))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The folder's children, sorted largest first. The swatch repeats the block's ramp
/// colour, so the list and the chart read as one surface.
struct StorageLedger: View {
    let folder: FolderNode
    let palette: TreemapPalette
    let selected: Set<URL>
    let hovered: URL?
    let isEnabled: Bool
    let hasReadErrors: Bool
    let onToggle: (FolderNode) -> Void
    let onOpen: (FolderNode) -> Void
    let onReveal: (FolderNode) -> Void

    private var children: [FolderNode] {
        folder.children.sorted { $0.size > $1.size }
    }

    private var childrenBytes: Int64 {
        max(1, children.reduce(0) { $0 + $1.size })
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            if children.isEmpty {
                EmptyStateView(
                    title: "No folders here.",
                    message: "This folder has no readable children."
                )
                .padding(Spacing.s4)
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(children, id: \.url) { child in
                            StorageLedgerRow(
                                child: child,
                                share: CGFloat(child.size) / CGFloat(childrenBytes),
                                palette: palette,
                                isSelected: selected.contains(child.url),
                                isHovered: hovered == child.url,
                                isEnabled: isEnabled,
                                onToggle: { onToggle(child) },
                                onOpen: { onOpen(child) },
                                onReveal: { onReveal(child) })
                            if child.url != children.last?.url {
                                Hairline().padding(.leading, Spacing.s3)
                            }
                        }
                    }
                }
                // A folder change starts the list at the top. Without this the old
                // scroll offset can leave the shorter new list showing blank rows.
                .id(folder.url)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(width: 288)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Theme.hairline)
                .frame(width: 1)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s2) {
                Text(folder.url.lastPathComponent.isEmpty ? "Home" : folder.url.lastPathComponent)
                    .font(Typography.section)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .accessibilityIdentifier("storage.ledger.header")
                Spacer(minLength: Spacing.s2)
                Text(folder.size.formatted(.byteCount(style: .file)))
                    .font(Typography.metric)
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            }
            HStack(spacing: Spacing.s2) {
                Text(folder.url.path)
                    .font(Typography.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: Spacing.s2)
                Text("\(children.count) items")
                    .font(Typography.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
            }
            if hasReadErrors {
                StatusLabel(
                    text: "Some folders here could not be read.",
                    systemImage: "exclamationmark.triangle",
                    tone: .amber)
            }
        }
        .padding(.horizontal, Spacing.s3)
        .padding(.vertical, Spacing.s2)
    }
}

struct StorageLedgerRow: View {
    let child: FolderNode
    let share: CGFloat
    let palette: TreemapPalette
    let isSelected: Bool
    let isHovered: Bool
    let isEnabled: Bool
    let onToggle: () -> Void
    let onOpen: () -> Void
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: Spacing.s2) {
            Toggle(
                "", isOn: Binding(get: { isSelected }, set: { _ in onToggle() })
            )
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(!isEnabled)
            .accessibilityLabel("Collect \(child.url.lastPathComponent)")
            .accessibilityIdentifier("storage.row.\(child.url.lastPathComponent)")
            Rectangle()
                .fill(palette.colorShare(share))
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(child.url.lastPathComponent)
                .font(Typography.row)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: Spacing.s2)
            Text(child.size.formatted(.byteCount(style: .file)))
                .font(Typography.row)
                .monospacedDigit()
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
            if child.children.isEmpty {
                Color.clear.frame(width: 16, height: 1)
            } else {
                RowActionButton(
                    help: "Open \(child.url.lastPathComponent)",
                    accessibilityLabel: "Open \(child.url.lastPathComponent)",
                    identifier: "storage.open.\(child.url.lastPathComponent)",
                    action: onOpen,
                    label: {
                        Image(systemName: "chevron.right")
                            .font(Typography.caption)
                            .foregroundStyle(Theme.inkSecondary)
                            .frame(width: 16, height: Metrics.rowHeight)
                    })
            }
        }
        .padding(.horizontal, Spacing.s3)
        .frame(height: Metrics.rowHeight)
        .background(isSelected || isHovered ? Theme.accentSoft : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onOpen() }
        .contextMenu {
            Button("Show in Finder") { onReveal() }
        }
        .help(child.url.path)
        .accessibilityElement(children: .contain)
    }
}
