import ChetCore
import SwiftUI

/// Home: capacity, what can be reclaimed, the scan state, and the two ledgers. No chart,
/// no card stack, no marketing hero.
struct OverviewView: View {
    @Environment(ScanModel.self) private var model
    @Binding var selection: String?
    let onClean: () -> Void
    @State private var showingScope = false

    var body: some View {
        PageScreen(
            header: { pageHeader },
            content: {
                capacity
                if model.isPartialScan { scopeNotice }
                content
            },
            bar: { commandBar }
        )
        .sheet(isPresented: $showingScope) { ScanScopeSheet() }
        .onAppear {
            VerboseLog.event(.debug, .ui, .uiViewAppeared, .code(.view, .viewHome))
        }
        .onChange(of: showingScope) { _, showing in
            if showing {
                VerboseLog.event(.debug, .ui, .uiSheetPresented, .code(.sheet, .sheetScanScope))
            }
        }
    }

    private var scopeNotice: some View {
        HStack(spacing: Spacing.s3) {
            StatusLabel(
                text: "Partial scan: \(model.resultScopeSummary)",
                systemImage: "circle.lefthalf.filled", tone: .amber)
            Spacer(minLength: Spacing.s3)
            QuietActionButton(
                title: "Scan everything", help: "Measure the whole Mac again"
            ) {
                model.scanEverything()
            }
            .accessibilityIdentifier("home.scan.everything")
        }
        .pageHorizontalPadding()
    }

    private var pageHeader: some View {
        PageHeader(
            title: "Clean up your Mac",
            subtitle: subtitle,
            metric: metric,
            metricLabel: "can be reclaimed"
        )
        .accessibilityIdentifier("home.header")
    }

    private var metric: String? {
        guard model.lastScan != nil, !model.isScanning, model.totalBytes > 0 else { return nil }
        return model.totalBytes.formatted(.byteCount(style: .file))
    }

    private var accessMissing: Bool {
        model.categories.contains(where: \.needsFullDiskAccess)
    }

    private var measuredRoots: [String] {
        let scopeRoots = model.resultScope.roots
        return scopeRoots.isEmpty ? [TestEnvironment.paths.root.path] : scopeRoots
    }

    private var blockingReadErrors: [WalkError] {
        guard !accessMissing else { return [] }
        return model.readErrors.filter {
            ReadScope.classify($0, roots: measuredRoots) == .categoryRoot
        }
    }

    private var state: HomeState {
        HomeState.resolve(
            isScanning: model.isScanning,
            hasScanned: model.lastScan != nil,
            didFinishScan: model.didFinishScan,
            totalBytes: model.totalBytes,
            blockingReadErrorCount: blockingReadErrors.count,
            needsFullDiskAccess: accessMissing)
    }

    private var subtitle: String {
        if let subtitle = state.subtitle { return subtitle }
        let count = rows(in: .safe).count + rows(in: .review).count
        return "\(count) \(count == 1 ? "category" : "categories"). Pick one to review."
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
        let blockingCount = blockingReadErrors.count
        VStack(alignment: .leading, spacing: Spacing.s4) {
            if blockingCount > 0 {
                VStack(alignment: .leading, spacing: Spacing.s2) {
                    StatusLabel(
                        text: "\(blockingCount) "
                            + (blockingCount == 1 ? "folder" : "folders")
                            + " could not be read.",
                        systemImage: "exclamationmark.triangle",
                        tone: .amber)
                    DisclosureGroup("Details") {
                        ForEach(
                            Array(blockingReadErrors.prefix(3).enumerated()),
                            id: \.offset
                        ) { _, error in
                            Text(error.url.path)
                                .font(Typography.caption)
                                .foregroundStyle(Theme.inkSecondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            if state == .scanning {
                scanProgress
            } else if state == .neverScanned {
                neverScanned
            } else {
                ledgers
            }
        }
    }

    private var neverScanned: some View {
        EmptyStateView(
            title: "No scan yet",
            message: "Run a scan to see what can be reclaimed."
        )
        .accessibilityIdentifier("home.empty")
    }

    @ViewBuilder private var ledgers: some View {
        let safe = rows(in: .safe)
        let review = rows(in: .review)
        VStack(alignment: .leading, spacing: Spacing.s6) {
            if safe.isEmpty && review.isEmpty, let title = state.emptyTitle,
                let message = state.emptyMessage
            {
                EmptyStateView(title: title, message: message, identifier: "home.empty")
                    .accessibilityIdentifier(
                        state == .unreadable ? "home.unreadable" : "home.empty")
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
        return RowActionButton(
            help: CategoryCopy.explanation(category.id),
            action: { selection = category.id },
            label: {
                HStack(spacing: Spacing.s3) {
                    Image(systemName: CategoryStyle.of(category.id).symbol)
                        .font(Typography.iconRow)
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
                .frame(minHeight: Metrics.rowHeight)
            })
    }

    private func categorySubtitle(_ category: CategoryState) -> String {
        if category.id == "snapshots" {
            return "macOS reports size only when deleted."
        }
        return category.items.count == 1 ? "1 file" : "\(category.items.count) files"
    }

    private func categoryValue(_ category: CategoryState) -> String {
        if category.id == "snapshots" {
            let count = model.snapshots.count
            return count == 1 ? "1 snapshot" : "\(count) snapshots"
        }
        return category.bytes.formatted(.byteCount(style: .file))
    }

    private var scanProgress: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            VStack(spacing: Spacing.s2) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
                    Text("Scanning caches and logs")
                        .font(Typography.section)
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Text("\(Int((progressFraction * 100).rounded()))%")
                        .font(Typography.metric)
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                }
                Hairline()
            }
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
                            .font(Typography.caption)
                            .foregroundStyle(Theme.inkSecondary)
                            .accessibilityHidden(true)
                        Text(ScanStepCopy.title(step.id))
                            .font(Typography.row)
                            .foregroundStyle(step.done ? Theme.inkSecondary : Theme.ink)
                        Spacer()
                    }
                    .padding(.vertical, Spacing.s1)
                }
            }
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
        if model.isScanning {
            CommandBar(
                metric: "\(Int((progressFraction * 100).rounded()))%",
                detail: activityLabel,
                actionTitle: "Stop scan",
                actionSystemImage: "stop.circle",
                secondaryTitle: model.isPaused ? "Resume" : "Pause",
                secondaryAction: { model.togglePause() },
                help: "Stop the scan",
                accessibilityLabel: "Stop the scan",
                disabledReason: nil,
                primaryIdentifier: "home.stop",
                secondaryIdentifier: model.isPaused ? "home.resume" : "home.pause",
                action: { model.cancel() })
        } else if model.lastScan == nil {
            CommandBar(
                metric: "Not measured",
                detail: "No scan yet",
                actionTitle: "Scan this Mac",
                actionSystemImage: "magnifyingglass",
                secondaryTitle: "Scope…",
                secondaryAction: { showingScope = true },
                help: "Scan for caches, logs, and large files (Command-R)",
                accessibilityLabel: "Scan for caches, logs, and large files",
                primaryIdentifier: "home.scan",
                secondaryIdentifier: "home.scope",
                action: { model.scan() })
        } else if model.selectedItems.isEmpty {
            CommandBar(
                metric: model.totalBytes.formatted(.byteCount(style: .file)),
                detail: model.categories.count == 1
                    ? "1 category" : "\(model.categories.count) categories",
                actionTitle: "Scan again",
                actionSystemImage: "magnifyingglass",
                secondaryTitle: "Scope…",
                secondaryAction: { showingScope = true },
                help: "Scan for caches, logs, and large files (Command-R)",
                accessibilityLabel: "Scan for caches, logs, and large files",
                primaryIdentifier: "home.scan",
                secondaryIdentifier: "home.scope",
                action: { model.scan() })
        } else {
            let count = model.selectedItems.count
            CommandBar(
                metric: model.selectedBytes.formatted(.byteCount(style: .file)),
                detail: count == 1 ? "1 item selected" : "\(count) items selected",
                actionTitle: "Clean selected",
                actionSystemImage: "trash",
                isEnabled: !model.isCleaning,
                secondaryTitle: "Scan again",
                secondaryAction: { model.scan() },
                help: "Review and clean the selected items",
                accessibilityLabel: "Clean selected, \(count) items",
                disabledReason: "Cleaning is running.",
                secondaryIdentifier: "home.rescan",
                action: {
                    model.beginClean()
                    onClean()
                })
        }
    }
}
