import ChetCore
import SwiftUI

/// The review step before Homebrew deletes old versions and the download cache. Homebrew
/// reports no byte total for either, so the rows name the targets and claim no size.
struct HomebrewCleanupSheet: View {
    @Environment(HomebrewModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetFrame {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text("Remove old versions?")
                        .font(Typography.title)
                        .foregroundStyle(Theme.ink)
                    Text("Homebrew deletes the old versions and the download cache.")
                        .font(Typography.body)
                        .foregroundStyle(Theme.inkSecondary)
                }
                SheetLedgerBox(maxHeight: nil) {
                    VStack(spacing: 0) {
                        row("Old package versions", detail: "Superseded by the installed version")
                        Hairline()
                        row("Download cache", detail: "Archives Homebrew downloaded")
                    }
                    .padding(.vertical, Spacing.s2)
                }
                Text("Current versions stay installed.")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.inkSecondary)
                if DryRun.enabled {
                    PreviewNotice(text: PreviewCopy.removals)
                }
                HStack {
                    Spacer()
                    SecondaryActionButton(title: "Cancel", shortcut: .return, action: { dismiss() })
                    DestructiveActionButton(
                        title: "Remove",
                        isEnabled: model.canAct,
                        help: "Delete the old versions and the download cache",
                        action: {
                            model.cleanup()
                            dismiss()
                        })
                }
            }
            .onExitCommand { dismiss() }
        }
    }

    private func row(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(Typography.row)
                .foregroundStyle(Theme.ink)
            Text(detail)
                .font(Typography.caption)
                .foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.s1)
    }
}
