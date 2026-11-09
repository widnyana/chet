import ChetCore
import SwiftUI

struct ConfirmSheet: View {
    @Environment(ScanModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let items = model.confirmItems
        let rows = Dictionary(grouping: items, by: \.categoryID)
            .map { CleanRow(id: $0.key, bytes: $0.value.reduce(0) { $0 + $1.reclaimableBytes }) }
            .sorted { $0.bytes > $1.bytes }
        let permanent = items.filter { $0.mode == .permanent }.reduce(0) { $0 + $1.reclaimableBytes }
        let trashed = items.filter { $0.mode == .trash }.reduce(0) { $0 + $1.reclaimableBytes }
        let totalCount = items.count + model.confirmSnapshots.count
        let groupCount = rows.count + (model.confirmSnapshots.isEmpty ? 0 : 1)
        let itemText = totalCount == 1 ? "1 item" : "\(totalCount) items"
        let hasPermanent = items.contains { $0.mode == .permanent } || !model.confirmSnapshots.isEmpty
        let hasTrash = items.contains { $0.mode == .trash }
        let title =
            hasPermanent && hasTrash
            ? "Clean \(itemText)?" : (hasTrash ? "Move \(itemText) to the Trash?" : "Delete \(itemText)?")
        let action = hasPermanent && hasTrash ? "Clean" : (hasTrash ? "Move to Trash" : "Delete")
        SheetFrame {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text(title)
                        .font(Typography.title)
                        .foregroundStyle(Theme.ink)
                    Text("\(itemText) in \(groupCount == 1 ? "1 category" : "\(groupCount) categories")")
                        .font(Typography.body)
                        .foregroundStyle(Theme.inkSecondary)
                        .monospacedDigit()
                }
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(rows) { row in
                            HStack(spacing: Spacing.s2) {
                                Image(systemName: CategoryStyle.of(row.id).symbol)
                                    .foregroundStyle(Theme.inkSecondary)
                                    .frame(width: 22)
                                Text(CategoryCopy.title(row.id, fallback: row.id))
                                    .font(Typography.row)
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                Text(row.bytes.formatted(.byteCount(style: .file)))
                                    .font(Typography.row)
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.inkSecondary)
                            }
                            .padding(.vertical, Spacing.s1)
                        }
                        if !model.confirmSnapshots.isEmpty {
                            HStack(spacing: Spacing.s2) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundStyle(Theme.inkSecondary)
                                    .frame(width: 22)
                                Text(
                                    model.confirmSnapshots.count == 1
                                        ? "1 Time Machine local snapshot"
                                        : "\(model.confirmSnapshots.count) Time Machine local snapshots"
                                )
                                .font(Typography.row)
                                Spacer()
                            }
                            .padding(.vertical, Spacing.s1)
                        }
                    }
                    .padding(.horizontal, Spacing.s3)
                    .padding(.vertical, Spacing.s2)
                }
                .frame(maxHeight: 220)
                .background(Theme.paperRaised, in: .rect(corners: .fixed(6)))
                VStack(alignment: .leading, spacing: Spacing.s2) {
                    if permanent > 0 {
                        HStack(spacing: Spacing.s2) {
                            Image(systemName: "trash.slash")
                                .foregroundStyle(Theme.inkSecondary)
                            Text(
                                DryRun.enabled
                                    ? "\(permanent.formatted(.byteCount(style: .file))) would be deleted. Apps rebuild these files."
                                    : "\(permanent.formatted(.byteCount(style: .file))) is deleted now. Apps rebuild these files."
                            )
                            .font(Typography.body)
                            .foregroundStyle(Theme.ink)
                        }
                    }
                    if trashed > 0 {
                        HStack(spacing: Spacing.s2) {
                            Image(systemName: "trash")
                                .foregroundStyle(Theme.inkSecondary)
                            Text(
                                DryRun.enabled
                                    ? "\(trashed.formatted(.byteCount(style: .file))) would move to the Trash."
                                    : "\(trashed.formatted(.byteCount(style: .file))) moves to the Trash. You can restore it from the Trash."
                            )
                            .font(Typography.body)
                            .foregroundStyle(Theme.ink)
                        }
                    }
                }
                Text(
                    DryRun.enabled
                        ? "Every item would be checked again before removal. Files that changed would be left alone."
                        : "Every item is checked again before removal. Files that changed are left alone."
                )
                .font(Typography.caption)
                .foregroundStyle(Theme.inkSecondary)
                if DryRun.enabled {
                    StatusLabel(
                        text: "Preview only. Nothing will be removed.",
                        systemImage: "exclamationmark.triangle",
                        tone: .amber)
                }
                HStack {
                    Spacer()
                    SecondaryActionButton(title: "Cancel", shortcut: .return, action: { dismiss() })
                    DestructiveActionButton(
                        title: action,
                        isEnabled: true,
                        help: "\(action) \(itemText)",
                        accessibilityLabel: "\(action) \(itemText)",
                        action: { model.clean() })
                }
            }
            .onExitCommand { dismiss() }
        }
    }

    private struct CleanRow: Identifiable {
        let id: String
        let bytes: Int64
    }
}
