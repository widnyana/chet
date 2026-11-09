import ChetCore
import SwiftUI

struct SnapshotsView: View {
    @Environment(ScanModel.self) private var model
    let onClean: () -> Void
    @State private var newestFirst = true
    @State private var reloading = false

    private var ordered: [LocalSnapshot] {
        model.snapshots.sorted { newestFirst ? $0.date > $1.date : $0.date < $1.date }
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                title: "Local snapshots",
                subtitle: "macOS reports size only when deleted.",
                metric: "\(model.snapshots.count)",
                metricLabel: model.snapshots.count == 1 ? "snapshot" : "snapshots"
            )
            .pageHorizontalPadding()
            .padding(.top, Spacing.s6)
            .padding(.bottom, Spacing.s3)
            if !model.snapshotErrors.isEmpty {
                errorState
            }
            if model.snapshots.isEmpty {
                if model.isScanning {
                    LoadingStateView(message: "Checking snapshots")
                        .pageHorizontalPadding()
                } else {
                    EmptyStateView(
                        title: "No local snapshots",
                        message: "Time Machine keeps them only while it has room.")
                }
            } else {
                sectionHeader
                table
            }
        }
        .background(Theme.paper)
        .safeAreaInset(edge: .bottom) {
            CommandBar(
                metric: "\(model.selectedSnapshots.count)",
                detail: model.selectedSnapshots.count == 1
                    ? "1 snapshot selected" : "\(model.selectedSnapshots.count) snapshots selected",
                actionTitle: "Clean selected",
                actionSystemImage: "trash",
                isEnabled: !model.selectedSnapshots.isEmpty && !model.isCleaning,
                help: "Review and clean the selected snapshots",
                accessibilityLabel:
                    "Clean selected, \(model.selectedSnapshots.count) snapshots",
                action: onClean)
        }
    }

    private var table: some View {
        ColumnTable(items: ordered) {
            header
        } row: { snapshot in
            row(snapshot)
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.s3) {
                Color.clear.frame(width: SnapshotColumns.mark)
                Text("Date")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Age")
                    .frame(width: SnapshotColumns.age, alignment: .trailing)
                Text("Local")
                    .frame(width: SnapshotColumns.local, alignment: .trailing)
            }
            .font(Typography.caption)
            .pageHorizontalPadding()
            .padding(.vertical, Spacing.s2)
            Hairline()
        }
    }

    private func row(_ snapshot: LocalSnapshot) -> some View {
        let selected = model.selectedSnapshots.contains(snapshot)
        return HStack(spacing: Spacing.s3) {
            Toggle("Remove the snapshot", isOn: model.isSelected(snapshot))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .accessibilityLabel("Remove the snapshot from \(Self.label(snapshot.date))")
                .frame(width: SnapshotColumns.mark)
            Text(Self.label(snapshot.date))
                .font(Typography.row)
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            ageCell(snapshot)
                .frame(width: SnapshotColumns.age, alignment: .trailing)
            Text("Local")
                .font(Typography.caption)
                .foregroundStyle(Theme.inkSecondary)
                .frame(width: SnapshotColumns.local, alignment: .trailing)
        }
        .frame(minHeight: Metrics.rowHeight)
        .pageHorizontalPadding()
        .background(selected ? Theme.accentSoft : Color.clear)
    }

    @ViewBuilder private func ageCell(_ snapshot: LocalSnapshot) -> some View {
        if let date = Self.date(snapshot.date) {
            Text(date, format: .relative(presentation: .named))
                .font(Typography.caption)
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
                .help(date.formatted(date: .long, time: .shortened))
        } else {
            Text("Unknown")
                .font(Typography.caption)
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    private var errorState: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            StatusLabel(
                text: "Could not read local snapshots",
                systemImage: "exclamationmark.triangle",
                tone: .red)
            Text("The snapshot command failed. Try again later.")
                .font(Typography.body)
                .foregroundStyle(Theme.inkSecondary)
            SecondaryActionButton(
                title: reloading ? "Trying again…" : "Try again",
                isEnabled: !reloading,
                help: "Read the local snapshots again",
                action: {
                    Task {
                        reloading = true
                        await model.reloadSnapshots()
                        reloading = false
                    }
                })
            DisclosureGroup("Details") {
                Text(model.snapshotErrors.joined(separator: "\n"))
                    .font(Typography.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pageHorizontalPadding()
        .padding(.bottom, Spacing.s2)
    }

    private static let parser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter
    }()

    private static func date(_ raw: String) -> Date? {
        parser.date(from: raw)
    }

    /// `2026-11-03-101500` becomes a localized date. Anything else is shown as reported.
    static func label(_ raw: String) -> String {
        guard let date = date(raw) else { return raw }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private var sectionHeader: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Snapshots")
                    .font(Typography.section)
                    .foregroundStyle(Theme.ink)
                Spacer()
                QuietActionButton(
                    title: newestFirst ? "Newest first" : "Oldest first",
                    help: "Change the sort order",
                    action: { newestFirst.toggle() })
            }
            .pageHorizontalPadding()
            .padding(.vertical, Spacing.s2)
            Hairline()
        }
    }
}

private enum SnapshotColumns {
    static let mark: CGFloat = 20
    static let age: CGFloat = 140
    static let local: CGFloat = 110
}
