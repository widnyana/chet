import MackitCore
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
                title: "Local snapshots",
                subtitle: "Time Machine keeps these on the startup disk while it has room.",
                metric: "\(model.snapshots.count)",
                metricLabel: model.snapshots.count == 1 ? "snapshot" : "snapshots"
            )
            .padding(.horizontal, Metrics.widePageMargin)
            .padding(.top, Spacing.s6)
            .padding(.bottom, Spacing.s3)
            if !model.snapshotErrors.isEmpty {
                ErrorStateView(
                    title: "Snapshot command failed",
                    message: model.snapshotErrors.joined(separator: "\n")
                )
                .padding(.horizontal, Spacing.s6)
            }
            if model.snapshots.isEmpty {
                if model.isScanning {
                    LoadingStateView(message: "Checking snapshots")
                        .padding(.horizontal, Spacing.s6)
                } else {
                    EmptyStateView(
                        title: "No local snapshots",
                        message: "Time Machine keeps local snapshots only while it has room on the disk.",
                        actionTitle: "Scan this Mac",
                        action: { model.scan() }
                    )
                    .padding(.horizontal, Spacing.s6)
                }
                Spacer()
            } else {
                sectionHeader
                List(ordered, id: \.self) { snapshot in
                    HStack(spacing: Spacing.s3) {
                        Toggle("Select snapshot", isOn: model.isSelected(snapshot))
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            .accessibilityLabel("Select \(Self.label(snapshot.date))")
                        Text(Self.label(snapshot.date))
                            .font(Typography.row)
                            .monospacedDigit()
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text("Local snapshot")
                            .font(Typography.caption)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    .padding(.vertical, 2)
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
                actionTitle: "Clean selected",
                actionSystemImage: "checkmark",
                isEnabled: !model.selectedSnapshots.isEmpty && !model.isCleaning,
                help: "Review and clean the selected snapshots",
                action: onClean)
        }
        .navigationTitle("Local snapshots")
    }

    /// `2026-11-03-101500` -> `2026-11-03 10:15`.
    static func label(_ raw: String) -> String {
        let parts = raw.split(separator: "-")
        guard parts.count == 4, parts[3].count >= 4 else { return raw }
        let time = parts[3]
        let hour = time.prefix(2)
        let minute = time.dropFirst(2).prefix(2)
        return "\(parts[0])-\(parts[1])-\(parts[2]) \(hour):\(minute)"
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
