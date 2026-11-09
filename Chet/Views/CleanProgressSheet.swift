import ChetCore
import SwiftUI

/// One sheet for the whole clean flow. Confirmation becomes progress in place,
/// then progress becomes the summary. The sheet cannot be dismissed while the
/// clean pass is running.
struct CleanFlowSheet: View {
    @Environment(ScanModel.self) private var model

    var body: some View {
        Group {
            if model.isCleaning {
                CleanProgressSheet()
            } else if let report = model.report {
                SummaryView(report: report)
            } else {
                ConfirmSheet()
            }
        }
        .interactiveDismissDisabled(model.isCleaning)
    }
}

struct CleanProgressSheet: View {
    @Environment(ScanModel.self) private var model

    var body: some View {
        let progress = model.cleanProgress
        let dryRun = DryRun.enabled
        let itemFraction = progress?.itemFraction ?? 0
        VStack(alignment: .leading, spacing: Spacing.s4) {
            HStack(spacing: Spacing.s3) {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text(dryRun ? "Previewing removal" : title)
                        .font(Typography.title)
                        .foregroundStyle(Theme.ink)
                    Text(headline(progress))
                        .font(Typography.body)
                        .foregroundStyle(Theme.inkSecondary)
                        .monospacedDigit()
                }
                Spacer(minLength: Spacing.s3)
                Text("\(Int((itemFraction * 100).rounded()))%")
                    .font(Typography.metric)
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
            }
            ProgressView(value: itemFraction)
                .tint(Theme.accent)
            detailBox(progress, dryRun: dryRun)
            Text("Chet checks each file again before removing it. Files and folders are both checked.")
                .font(Typography.caption)
                .foregroundStyle(Theme.inkSecondary)
        }
        .padding(Spacing.s6)
        .frame(width: 520)
        .background(Theme.paper)
    }

    private var hasTrash: Bool { model.confirmItems.contains { $0.mode == .trash } }
    private var hasPermanent: Bool {
        model.confirmItems.contains { $0.mode == .permanent } || !model.confirmSnapshots.isEmpty
    }

    private var title: String {
        if hasPermanent && hasTrash { return "Removing files" }
        return hasTrash ? "Moving files to the Trash" : "Deleting files"
    }

    private func currentAction(_ progress: CleanProgress, dryRun: Bool) -> String {
        if dryRun {
            return progress.currentMode == .permanent ? "Would delete" : "Would move to Trash"
        }
        return progress.currentMode == .permanent ? "Deleting" : "Moving to Trash"
    }

    private func headline(_ progress: CleanProgress?) -> String {
        guard let progress else { return "Getting ready" }
        if progress.isFinal {
            return model.cleanSnapshotCount > 0 ? "Finishing Time Machine snapshots" : "Finishing"
        }
        if progress.currentPath.isEmpty { return "Getting ready" }
        return "File \(progress.currentFileNumber) of \(progress.total)"
    }

    private func detailBox(_ progress: CleanProgress?, dryRun: Bool) -> some View {
        let processedBytes = progress?.processedBytes ?? 0
        let totalBytes = progress?.totalBytes ?? 0
        let freedBytes = progress?.freedBytes ?? 0
        return VStack(spacing: 0) {
            detailRow("Files", "\(progress?.processed ?? 0) of \(progress?.total ?? 0)")
            Hairline()
            VStack(alignment: .leading, spacing: Spacing.s1) {
                HStack {
                    Text("Size")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.inkSecondary)
                    Spacer()
                    Text(
                        "\(processedBytes.formatted(.byteCount(style: .file))) of \(totalBytes.formatted(.byteCount(style: .file)))"
                    )
                    .font(Typography.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.inkSecondary)
                }
                ProgressView(value: progress?.byteFraction ?? 0)
                    .tint(Theme.accent)
            }
            .padding(.vertical, Spacing.s2)
            Hairline()
            detailRow(
                dryRun ? "Would free" : "Freed",
                freedBytes.formatted(.byteCount(style: .file)))
            if let progress, progress.skipped > 0 {
                Hairline()
                detailRow(dryRun ? "Would skip" : "Skipped", "\(progress.skipped)")
            }
            if let progress, progress.failed > 0 {
                Hairline()
                detailRow(dryRun ? "Would leave" : "Could not remove", "\(progress.failed)")
            }
            if model.cleanSnapshotCount > 0 {
                Hairline()
                detailRow("Snapshots", "\(model.cleanSnapshotCount)")
            }
            Hairline()
            currentRow(progress, dryRun: dryRun)
        }
        .padding(Spacing.s4)
        .background(Theme.paperRaised, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(Theme.inkSecondary)
            Spacer()
            Text(value)
                .font(Typography.row)
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
        }
        .padding(.vertical, Spacing.s1)
    }

    private func currentRow(_ progress: CleanProgress?, dryRun: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Current")
                .font(Typography.caption)
                .foregroundStyle(Theme.inkSecondary)
            if let progress, !progress.isFinal, !progress.currentPath.isEmpty {
                Text(progress.currentPath)
                    .font(Typography.row)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(progress.currentPath)
                    .textSelection(.enabled)
                HStack(spacing: Spacing.s2) {
                    Text(progress.currentIsDirectory ? "Folder" : "File")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.inkSecondary)
                    Text(currentAction(progress, dryRun: dryRun))
                        .font(Typography.caption)
                        .foregroundStyle(Theme.inkSecondary)
                    Text(progress.currentBytes.formatted(.byteCount(style: .file)))
                        .font(Typography.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.inkSecondary)
                }
            } else if let progress, progress.isFinal {
                Text("Finishing")
                    .font(Typography.row)
                    .foregroundStyle(Theme.inkSecondary)
            } else {
                Text("Getting ready")
                    .font(Typography.row)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .padding(.vertical, Spacing.s1)
    }
}
