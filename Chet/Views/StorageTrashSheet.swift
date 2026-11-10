import ChetCore
import SwiftUI

/// Confirmation for the Storage collection. Lists what will move and repeats the
/// recoverable consequence in one sentence.
struct StorageTrashSheet: View {
    let entries: [StorageEntry]
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var bytes: Int64 {
        entries.reduce(0) { $0 + $1.bytes }
    }

    private var shown: [StorageEntry] {
        Array(entries.prefix(6))
    }

    private var title: String {
        let count = entries.count
        return "Move \(count) \(count == 1 ? "item" : "items") to the Trash?"
    }

    var body: some View {
        SheetFrame {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                Text(title)
                    .font(Typography.title)
                    .foregroundStyle(Theme.ink)
                    .accessibilityIdentifier("storage.trashTitle")
                Text("Moved items stay in the Trash until you empty it.")
                    .font(Typography.body)
                    .foregroundStyle(Theme.inkSecondary)
                VStack(spacing: 0) {
                    ForEach(shown) { entry in
                        HStack(spacing: Spacing.s3) {
                            Text(entry.name)
                                .font(Typography.row)
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: Spacing.s3)
                            Text(entry.bytes.formatted(.byteCount(style: .file)))
                                .font(Typography.row)
                                .monospacedDigit()
                                .foregroundStyle(Theme.inkSecondary)
                        }
                        .frame(height: 28)
                        if entry.id != shown.last?.id {
                            Hairline()
                        }
                    }
                    if entries.count > shown.count {
                        HStack {
                            Text("and \(entries.count - shown.count) more")
                                .font(Typography.caption)
                                .foregroundStyle(Theme.inkSecondary)
                            Spacer()
                            Text(bytes.formatted(.byteCount(style: .file)))
                                .font(Typography.caption)
                                .monospacedDigit()
                                .foregroundStyle(Theme.inkSecondary)
                        }
                        .frame(height: 28)
                    }
                }
                .padding(.horizontal, Spacing.s3)
                .padding(.vertical, Spacing.s1)
                .background(Theme.paperRaised, in: .rect(corners: .fixed(Metrics.controlRadius)))
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 1)
                }
                if DryRun.enabled {
                    StatusLabel(
                        text: "Preview only. Nothing will be moved.",
                        systemImage: "exclamationmark.triangle",
                        tone: .amber)
                }
                HStack(spacing: Spacing.s3) {
                    Spacer()
                    SecondaryActionButton(title: "Cancel") { dismiss() }
                        .accessibilityIdentifier("storage.trashCancel")
                    DestructiveActionButton(
                        title: "Move to Trash",
                        isEnabled: !DryRun.enabled,
                        help: "Move the collected folders to the Trash.",
                        action: onConfirm
                    )
                    .accessibilityIdentifier("storage.trashConfirm")
                }
            }
            .onExitCommand { dismiss() }
        }
    }
}
