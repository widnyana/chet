import ChetCore
import SwiftUI

struct TrashHistorySheet: View {
    @Environment(ScanModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var report: RestoreReport?

    private var operations: [TrashOperation] {
        model.trashLedger.restorableOperations()
    }

    var body: some View {
        SheetFrame {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                Text("Restore from the Trash")
                    .font(Typography.title)
                    .foregroundStyle(Theme.ink)
                if operations.isEmpty {
                    Text("Nothing to restore.")
                        .font(Typography.body)
                        .foregroundStyle(Theme.inkSecondary)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(operations) { operation in
                                row(operation)
                                Hairline()
                            }
                        }
                    }
                }
                if let report {
                    VStack(alignment: .leading, spacing: Spacing.s1) {
                        Text("\(report.restored) items restored")
                            .font(Typography.body)
                            .foregroundStyle(Theme.ink)
                        ForEach(report.unavailable, id: \.entry.originalPath) { item in
                            Text(RefusalCopy.restore(item.reason))
                                .font(Typography.caption)
                                .foregroundStyle(Theme.inkSecondary)
                        }
                    }
                }
                HStack {
                    Spacer()
                    PrimaryActionButton(
                        title: "Done",
                        shortcut: .return,
                        action: { dismiss() })
                }
            }
        }
    }

    private func row(_ operation: TrashOperation) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(operation.date.formatted(date: .abbreviated, time: .shortened))
                    .font(Typography.row)
                    .foregroundStyle(Theme.ink)
                Text("\(operation.entries.count) items")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
            Spacer()
            SecondaryActionButton(
                title: "Restore",
                action: { report = model.trashLedger.restore(operation) }
            )
            .accessibilityIdentifier("storage.restore.\(operation.id.uuidString)")
        }
        .padding(.vertical, Spacing.s2)
    }
}
