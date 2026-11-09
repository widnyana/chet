import ChetCore
import SwiftUI

/// Pinned under the sidebar list: the startup disk's capacity and the Trash, with a way to
/// empty it. The capacity bar shows used against free; purgeable space is named below it.
struct SidebarFooter: View {
    @Environment(SystemStatusModel.self) private var status
    @State private var confirmingEmpty = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Hairline()
            if let capacity = status.capacity, capacity.total > 0 {
                capacityBlock(capacity)
            }
            trashRow
        }
        .padding(.horizontal, Spacing.s3)
        .padding(.vertical, Spacing.s2)
        .background(Theme.paper)
        .onAppear { status.refresh() }
        .confirmationDialog(
            "Empty the Trash?", isPresented: $confirmingEmpty, titleVisibility: .visible
        ) {
            Button("Empty Trash", role: .destructive) { status.emptyTrash() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes everything in your Trash.")
        }
    }

    private func capacityBlock(_ capacity: VolumeCapacity) -> some View {
        let used = max(0, capacity.total - capacity.free)
        return VStack(alignment: .leading, spacing: Spacing.s1) {
            HStack(spacing: Spacing.s2) {
                Text(capacity.name)
                    .font(Typography.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Spacer(minLength: Spacing.s2)
                Text("\(capacity.free.formatted(.byteCount(style: .file))) free")
                    .font(Typography.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.inkSecondary)
            }
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Theme.capacityUsed)
                        .frame(width: share(used, capacity.total) * geometry.size.width)
                    Rectangle()
                        .fill(Theme.capacityFree)
                }
            }
            .frame(height: 6)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            if capacity.purgeable > 0 {
                Text("\(capacity.purgeable.formatted(.byteCount(style: .file))) purgeable")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.inkTertiary)
                    .help("Space macOS frees automatically when it needs room.")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(capacity.name), \(capacity.free.formatted(.byteCount(style: .file))) free of \(capacity.total.formatted(.byteCount(style: .file)))"
        )
    }

    private var trashRow: some View {
        HStack(spacing: Spacing.s2) {
            Image(systemName: "trash")
                .font(Typography.caption)
                .foregroundStyle(Theme.inkSecondary)
                .frame(width: 16)
            Text("Trash")
                .font(Typography.caption)
                .foregroundStyle(Theme.ink)
            Spacer(minLength: Spacing.s2)
            if status.isEmptyingTrash {
                ProgressView().controlSize(.mini)
            } else {
                Text(status.trashBytes.formatted(.byteCount(style: .file)))
                    .font(Typography.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.inkSecondary)
                QuietActionButton(
                    title: "Empty",
                    isEnabled: status.trashBytes > 0,
                    accessibilityLabel: "Empty the Trash",
                    action: { confirmingEmpty = true })
            }
        }
    }

    private func share(_ part: Int64, _ total: Int64) -> CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(min(1, max(0, Double(part) / Double(total))))
    }
}
