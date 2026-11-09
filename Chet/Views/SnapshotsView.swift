import ChetCore
import SwiftUI

struct SnapshotsView: View {
    @Environment(ScanModel.self) private var model
    let onClean: () -> Void
    @State private var newestFirst = true

    private var ordered: [LocalSnapshot] {
        model.snapshots.sorted { newestFirst ? $0.date > $1.date : $0.date < $1.date }
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                title: "Time Machine snapshots",
                subtitle: "Local copies on this disk. Removing one does not delete your backups.",
                metric: "\(model.snapshots.count)",
                metricLabel: model.snapshots.count == 1 ? "snapshot" : "snapshots"
            )
            .padding(.horizontal, Metrics.widePageMargin)
            .padding(.top, Spacing.s6)
            .padding(.bottom, Spacing.s3)
            if !model.snapshotErrors.isEmpty {
                errorState
            }
            if model.snapshots.isEmpty {
                if model.isScanning {
                    LoadingStateView(message: "Checking for snapshots")
                        .padding(.horizontal, Spacing.s6)
                } else {
                    EmptyStateView(
                        title: "No Time Machine snapshots",
                        message: "There are no local snapshots to remove.",
                        systemImage: "clock.arrow.circlepath")
                }
            } else {
                sectionHeader
                List(ordered, id: \.self) { snapshot in
                    HStack(spacing: Spacing.s3) {
                        Toggle("Remove the snapshot", isOn: model.isSelected(snapshot))
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            .accessibilityLabel("Remove the snapshot from \(Self.label(snapshot.date))")
                        Text(Self.label(snapshot.date))
                            .font(Typography.row)
                            .monospacedDigit()
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text("Local snapshot")
                            .font(Typography.caption)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    .padding(.vertical, Spacing.s1)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .background(Theme.paper)
            }
        }
        .background(Theme.paper)
        .safeAreaInset(edge: .bottom) {
            CommandBar(
                metric: "\(model.selectedSnapshots.count)",
                detail: model.selectedSnapshots.count == 1
                    ? "1 snapshot selected" : "\(model.selectedSnapshots.count) snapshots selected",
                actionTitle: "Remove selected",
                actionSystemImage: "trash",
                isEnabled: !model.selectedSnapshots.isEmpty && !model.isCleaning,
                help: "Review and remove the selected snapshots",
                accessibilityLabel:
                    "Remove selected, \(model.selectedSnapshots.count) snapshots",
                action: onClean)
        }
    }

    private var errorState: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            StatusLabel(
                text: "Could not read local snapshots",
                systemImage: "exclamationmark.triangle",
                tone: .red)
            Text("macOS returned an error. Try again later.")
                .font(Typography.body)
                .foregroundStyle(Theme.inkSecondary)
            DisclosureGroup("Details") {
                Text(model.snapshotErrors.joined(separator: "\n"))
                    .font(Typography.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.s6)
        .padding(.bottom, Spacing.s2)
    }

    private static let parser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter
    }()

    /// `2026-11-03-101500` becomes a localized date. Anything else is shown as reported.
    static func label(_ raw: String) -> String {
        guard let date = parser.date(from: raw) else { return raw }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private var sectionHeader: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Snapshots")
                    .font(Typography.section)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button(newestFirst ? "Newest first" : "Oldest first") {
                    newestFirst.toggle()
                }
                .buttonStyle(.plain)
                .font(Typography.caption)
                .foregroundStyle(Theme.accent)
                .help("Change the sort order")
            }
            .padding(.horizontal, Spacing.s6)
            .padding(.vertical, Spacing.s2)
            Hairline()
        }
    }
}
