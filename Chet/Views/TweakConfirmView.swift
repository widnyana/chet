import ChetCore
import SwiftUI

/// The review step for a medium or high risk change. It states the value going in, the
/// value coming out, and what the change affects before the write happens.
struct TweakConfirmView: View {
    @Environment(TweaksModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let pending: PendingChange

    private var current: TweakValue? { model.reading(for: pending.tweak.id)?.current }

    var body: some View {
        SheetFrame {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text("Change \(pending.tweak.name)?")
                        .font(Typography.title)
                        .foregroundStyle(Theme.ink)
                    Text(pending.tweak.summary)
                        .font(Typography.body)
                        .foregroundStyle(Theme.inkSecondary)
                }
                StatusLabel(
                    text: TweakCopy.risk(pending.tweak.risk),
                    systemImage: "shield.lefthalf.filled",
                    tone: TweakCopy.riskTone(pending.tweak.risk))
                Text(pending.tweak.detail)
                    .font(Typography.body)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if model.isGated {
                    PreviewNotice(text: PreviewCopy.tweaks, tone: .inert)
                }
                VStack(spacing: 0) {
                    DefinitionRow(label: "From", value: TweakCopy.value(current))
                    Hairline()
                    DefinitionRow(label: "To", value: TweakCopy.value(pending.value))
                    Hairline()
                    DefinitionRow(label: "System impact", value: pending.tweak.impact)
                    Hairline()
                    DefinitionRow(label: "Applies", value: TweakCopy.restart(pending.tweak.restart))
                    Hairline()
                    DefinitionRow(
                        label: "If it fails",
                        value: "The earlier value is restored and the failure is recorded.")
                }
                HStack(spacing: Spacing.s3) {
                    SecondaryActionButton(title: "Cancel", shortcut: .return) {
                        model.cancelPendingChange()
                        dismiss()
                    }
                    Spacer(minLength: Spacing.s3)
                    PrimaryActionButton(title: "Change", isEnabled: !model.isGated) {
                        model.confirmPendingChange()
                        dismiss()
                    }
                }
            }
            .onExitCommand {
                model.cancelPendingChange()
                dismiss()
            }
        }
        .accessibilityIdentifier("tweak.confirm.\(pending.tweak.id)")
    }
}
