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
            VStack(alignment: .leading, spacing: Spacing.s1) {
                trashRow
            }
        }
        .padding(.horizontal, Spacing.s3)
        .padding(.vertical, Spacing.s2)
        .onAppear { status.refresh() }
        .confirmationDialog(
            "Empty the Trash?", isPresented: $confirmingEmpty, titleVisibility: .visible
        ) {
            Button("Empty Trash", role: .destructive) { status.emptyTrash() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                DryRun.enabled
                    ? "Preview only. Nothing will be removed." : "This permanently deletes everything in your Trash.")
        }
    }

    private func capacityBlock(_ capacity: VolumeCapacity) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            CapacityBarView(
                volumeName: capacity.name,
                total: capacity.total,
                free: capacity.free,
                reclaimable: 0,
                showsHeader: false,
                showsLegend: false,
                height: 10)
            if capacity.purgeable > 0 {
                Text("\(capacity.purgeable.formatted(.byteCount(style: .file))) purgeable")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .help("Space macOS frees automatically when it needs room.")
            }
        }
    }

    private var trashRow: some View {
        HStack(spacing: Spacing.s2) {
            Image(systemName: "trash")
                .font(Typography.caption)
                .foregroundStyle(Theme.inkSecondary)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text("Trash")
                .font(Typography.caption)
                .foregroundStyle(Theme.ink)
            Spacer(minLength: Spacing.s2)
            if status.isEmptyingTrash {
                Text("Emptying...")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.inkSecondary)
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
}
