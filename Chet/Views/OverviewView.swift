import ChetCore
import SwiftUI

/// Home: capacity, what can be freed, the scan state, and the two ledgers. No chart,
/// no card stack, no marketing hero.
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
        .safeAreaInset(edge: .bottom) { commandBar }
    }

    private var pageHeader: some View {
        PageHeader(
            title: "Clean up your Mac",
            subtitle: subtitle,
            metric: metric,
            metricLabel: "can be freed"
        )
        .accessibilityIdentifier("home.header")
    }

    private var metric: String? {
        guard model.lastScan != nil, !model.isScanning, model.totalBytes > 0 else { return nil }
        return model.totalBytes.formatted(.byteCount(style: .file))
    }

    private var subtitle: String {
        if model.isScanning { return "Scanning caches, logs, and large files." }
        guard model.lastScan != nil else {
            return "Scan for caches, logs, and large files. Nothing is removed until you choose."
        }
        if model.totalBytes == 0 { return "Your Mac is tidy." }
        return "You can free \(model.totalBytes.formatted(.byteCount(style: .file)))."
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
        VStack(alignment: .leading, spacing: Spacing.s4) {
            if !model.readErrors.isEmpty {
                StatusLabel(
                    text: "Some folders could not be read. Results may be incomplete.",
                    systemImage: "exclamationmark.triangle",
                    tone: .amber)
            }
            if !model.isScanning {
                HStack(spacing: Spacing.s3) {
                    PrimaryActionButton(
                        title: model.lastScan == nil ? "Scan" : "Scan again",
                        systemImage: "magnifyingglass",
                        help: "Scan for caches, logs, and large files (Command-R)",
                        accessibilityLabel: "Scan for caches, logs, and large files",
                        action: { model.scan() }
                    )
                    .accessibilityIdentifier("home.scan")
                    Spacer()
                }
            }
            if model.isScanning {
                scanProgress
            } else if model.lastScan == nil {
                neverScanned
            } else {
                ledgers
            }
        }
    }

    private var neverScanned: some View {
        EmptyStateView(
            title: "No scan yet",
            message: "A scan measures your folders and shows what takes space.",
            systemImage: "internaldrive"
        )
        .accessibilityIdentifier("home.empty")
    }

    @ViewBuilder private var ledgers: some View {
        let safe = rows(in: .safe)
        let review = rows(in: .review)
        VStack(alignment: .leading, spacing: Spacing.s6) {
            if safe.isEmpty && review.isEmpty {
                EmptyStateView(
                    title: "Nothing found",
                    message: "Scan again after you use more apps.",
                    systemImage: "checkmark.circle")
            }
            if !safe.isEmpty { ledger("Safe to remove", safe) }
            if !review.isEmpty { ledger("Check first", review) }
        }
    }

    /// Categories with something to remove, or the snapshots row when snapshots exist,
    /// largest first.
    private func rows(in section: CategorySection) -> [CategoryState] {
        model.categories
            .filter { $0.bytes > 0 || ($0.id == "snapshots" && !model.snapshots.isEmpty) }
            .filter { CategoryCopy.section($0.id, risk: $0.items.first?.risk) == section }
            .sorted { $0.bytes > $1.bytes }
    }

    private func ledger(_ title: String, _ categories: [CategoryState]) -> some View {
        let total = categories.reduce(Int64(0)) { $0 + $1.bytes }
        return VStack(alignment: .leading, spacing: Spacing.s3) {
            SectionHeader(
                title: title,
                trailing: total.formatted(.byteCount(style: .file)))
            VStack(spacing: 0) {
                ForEach(categories) { category in
                    categoryRow(category)
                    if category.id != categories.last?.id { Hairline() }
                }
            }
        }
    }

    private func categoryRow(_ category: CategoryState) -> some View {
        let title = CategoryCopy.title(category.id, fallback: category.title)
        return Button {
            selection = category.id
        } label: {
            HStack(spacing: Spacing.s3) {
                Image(systemName: CategoryStyle.of(category.id).symbol)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
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
        .help(CategoryCopy.explanation(category.id))
    }

    private func categorySubtitle(_ category: CategoryState) -> String {
        if category.id == "snapshots" {
            return model.snapshots.count == 1 ? "1 snapshot" : "\(model.snapshots.count) snapshots"
        }
        return category.items.count == 1 ? "1 file" : "\(category.items.count) files"
    }

    private func categoryValue(_ category: CategoryState) -> String {
        if category.id == "snapshots" {
            return model.snapshots.count == 1 ? "1" : "\(model.snapshots.count)"
        }
        return category.bytes.formatted(.byteCount(style: .file))
    }

    private var scanProgress: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            SectionHeader(title: "Scanning your Mac")
            ProgressView(value: progressFraction)
                .tint(Theme.accent)
            Text(activityLabel)
                .font(Typography.body)
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(activityLabel)
            VStack(spacing: 0) {
                ForEach(model.steps) { step in
                    HStack(spacing: Spacing.s2) {
                        Image(systemName: step.done ? "checkmark.circle" : "circle")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(step.done ? Theme.inkSecondary : Theme.inkTertiary)
                        Text(ScanStepCopy.title(step.id))
                            .font(Typography.row)
                            .foregroundStyle(step.done ? Theme.inkSecondary : Theme.ink)
                        Spacer()
                    }
                    .padding(.vertical, Spacing.s1)
                }
            }
            HStack(spacing: Spacing.s2) {
                SecondaryActionButton(
                    title: "Pause", isEnabled: !model.isPaused,
                    action: { model.togglePause() }
                )
                .accessibilityIdentifier("home.pause")
                SecondaryActionButton(
                    title: "Resume", isEnabled: model.isPaused,
                    action: { model.togglePause() }
                )
                .accessibilityIdentifier("home.resume")
            }
            .padding(.top, Spacing.s1)
        }
    }

    private var activityLabel: String {
        if let activity = model.activity { return activity.label }
        if let step = model.currentStep { return ScanStepCopy.title(step) }
        return "Starting scan"
    }

    private var progressFraction: Double {
        let total = max(model.steps.count, 1)
        return Double(model.steps.filter(\.done).count) / Double(total)
    }

    @ViewBuilder private var commandBar: some View {
        if !model.selectedItems.isEmpty && !model.isScanning {
            let count = model.selectedItems.count
            CommandBar(
                metric: model.selectedBytes.formatted(.byteCount(style: .file)),
                detail: count == 1 ? "1 item selected" : "\(count) items selected",
                actionTitle: "Remove selected",
                actionSystemImage: "trash",
                isEnabled: !model.isCleaning,
                help: "Review and remove the selected items",
                accessibilityLabel: "Remove selected, \(count) items",
                action: {
                    model.beginClean()
                    onClean()
                })
        }
    }
}
