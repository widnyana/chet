import MackitCore
import SwiftUI

/// The ledger: capacity, the reclaimable total, the scan state, and the
/// category rows. No chart, no card stack, no marketing hero.
struct OverviewView: View {
    @Environment(ScanModel.self) private var model
    @Binding var selection: String?
    let onClean: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s8) {
                pageHeader
                capacity
                content
            }
            .padding(.horizontal, Metrics.widePageMargin)
            .padding(.vertical, Spacing.s8)
            .frame(maxWidth: Metrics.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Theme.paper)
        .navigationTitle("Overview")
        .safeAreaInset(edge: .bottom) { commandBar }
    }

    private var pageHeader: some View {
        PageHeader(
            title: "Overview",
            subtitle: summaryLine,
            metric: model.isScanning
                ? model.totalBytes.formatted(.byteCount(style: .file))
                : (model.lastScan == nil ? "Not measured" : model.totalBytes.formatted(.byteCount(style: .file))),
            metricLabel: model.isScanning
                ? "found so far"
                : (model.lastScan == nil ? nil : "can be reclaimed"))
    }

    private var summaryLine: String {
        if model.lastScan == nil {
            return "A clear account of this disk."
        }
        if model.totalBytes == 0 {
            return "Nothing to reclaim. This Mac is tidy."
        }
        return "\(model.categories.count) categories, \(model.totalBytes.formatted(.byteCount(style: .file))) can be reclaimed."
    }

    private var capacity: some View {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeLocalizedNameKey,
        ])
        let total = Int64(values?.volumeTotalCapacity ?? 0)
        let free = values?.volumeAvailableCapacityForImportantUsage ?? 0
        return CapacityBarView(
            volumeName: values?.volumeLocalizedName ?? "Startup disk",
            total: total,
            free: free,
            reclaimable: model.totalBytes)
    }

    @ViewBuilder private var content: some View {
        if model.isScanning {
            scanProgress
        } else if model.lastScan == nil {
            EmptyStateView(
                title: "No scan yet",
                message: "Run a scan to see which folders can be cleaned and which items need review.")
        } else {
            categoryLedger
        }
    }

    private var categoryLedger: some View {
        let rows = model.categories.filter {
            $0.bytes > 0 || ($0.id == "snapshots" && !model.snapshots.isEmpty)
        }
        return VStack(alignment: .leading, spacing: Spacing.s3) {
            SectionHeader(
                title: "Reclaimable",
                trailing: rows.isEmpty ? nil : "\(rows.count) categories")
            if rows.isEmpty {
                EmptyStateView(
                    title: "Nothing to reclaim",
                    message: "The last scan found no reclaimable data. Scan again after you install or use more apps.",
                    actionTitle: "Scan again",
                    action: { model.scan() })
            } else {
                VStack(spacing: 0) {
                    ForEach(rows) { category in
                        categoryRow(category)
                        if category.id != rows.last?.id { Hairline() }
                    }
                }
            }
        }
    }

    private func categoryRow(_ category: CategoryState) -> some View {
        Button {
            selection = category.id
        } label: {
            HStack(spacing: Spacing.s3) {
                Image(systemName: CategoryStyle.of(category.id).symbol)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(category.title)
                        .font(Typography.row)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(categorySubtitle(category))
                        .font(Typography.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: Spacing.s3)
                Text(categoryValue(category))
                    .font(Typography.metric)
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            }
            .padding(.vertical, Spacing.s2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open \(category.title)")
    }

    private func categorySubtitle(_ category: CategoryState) -> String {
        if category.id == "snapshots" {
            return model.snapshots.count == 1 ? "1 snapshot" : "\(model.snapshots.count) snapshots"
        }
        return category.items.count == 1 ? "1 item" : "\(category.items.count) items"
    }

    private func categoryValue(_ category: CategoryState) -> String {
        if category.id == "snapshots" {
            return model.snapshots.count == 1 ? "1" : "\(model.snapshots.count)"
        }
        return category.bytes.formatted(.byteCount(style: .file))
    }

    private var scanProgress: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            SectionHeader(
                title: "Scanning",
                trailing: "\(Int((progressFraction * 100).rounded())) %")
            ProgressView(value: progressFraction)
                .tint(Theme.accent)
            if let activity = model.activity {
                Text(activity.label)
                    .font(Typography.body)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(activity.label)
            } else {
                Text(model.currentStep?.title ?? "Starting scan")
                    .font(Typography.body)
                    .foregroundStyle(Theme.inkSecondary)
            }
            VStack(spacing: 0) {
                ForEach(model.steps) { step in
                    HStack(spacing: Spacing.s2) {
                        Image(systemName: step.done ? "checkmark.circle" : "circle")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(step.done ? Theme.inkSecondary : Theme.inkTertiary)
                        Text(step.title)
                            .font(Typography.row)
                            .foregroundStyle(step.done ? Theme.inkSecondary : Theme.ink)
                        Spacer()
                    }
                    .padding(.vertical, Spacing.s1)
                }
            }
        }
    }

    private var progressFraction: Double {
        let total = max(model.steps.count, 1)
        return Double(model.steps.filter(\.done).count) / Double(total)
    }

    private var commandBar: some View {
        if model.isScanning {
            return CommandBar(
                metric: "Scanning",
                detail: model.activity?.label ?? "Starting",
                actionTitle: "Stop scan",
                actionSystemImage: "stop.fill",
                isEnabled: true,
                secondaryTitle: model.isPaused ? "Resume" : "Pause",
                secondaryAction: { model.togglePause() },
                action: { model.cancel() })
        }
        if model.lastScan == nil {
            return CommandBar(
                metric: "No ledger yet",
                detail: "Run a scan to build the ledger",
                actionTitle: "Scan this Mac",
                actionSystemImage: "magnifyingglass",
                action: { model.scan() })
        }
        let count = model.selectedItems.count
        return CommandBar(
            metric: model.selectedBytes.formatted(.byteCount(style: .file)),
            detail: count == 1 ? "1 item selected" : "\(count) items selected",
            actionTitle: "Clean selected",
            actionSystemImage: "checkmark",
            isEnabled: model.selectedBytes > 0 && !model.isCleaning,
            help: "Review and clean the selected items",
            action: {
                model.beginClean()
                onClean()
            })
    }
}
