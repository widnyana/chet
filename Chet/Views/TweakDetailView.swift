import ChetCore
import SwiftUI

/// One tweak in full: what it changes, its current value, the preference key behind it,
/// and the actions that change or revert it. The row keeps the fast control; this sheet
/// carries the consequence.
struct TweakDetailView: View {
    @Environment(TweaksModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let tweak: Tweak

    private var reading: TweakReading? { model.reading(for: tweak.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            header
            Hairline()
            Text(tweak.detail)
                .font(Typography.body)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.isGated {
                StatusLabel(
                    text: "Preview only. No tweak is changed.", systemImage: "eye.slash",
                    tone: .amber)
            }
            facts
            actions
                .disabled(model.isGated)
        }
        .padding(Spacing.s6)
        .frame(width: 540, alignment: .leading)
        .background(Theme.paper)
        .accessibilityIdentifier("tweak.detail.\(tweak.id)")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tweak.name)
                    .font(Typography.title)
                    .foregroundStyle(Theme.ink)
                Text(tweak.summary)
                    .font(Typography.body)
                    .foregroundStyle(Theme.inkSecondary)
            }
            Spacer(minLength: Spacing.s3)
            IconActionButton(systemImage: "xmark", label: "Close") { dismiss() }
        }
    }

    private var facts: some View {
        VStack(spacing: 0) {
            DefinitionRow(label: "Current state", value: TweakCopy.state(reading?.state ?? .unknown("Not read")))
            Hairline()
            DefinitionRow(label: "System impact", value: tweak.impact)
            Hairline()
            DefinitionRow(label: "Risk", value: TweakCopy.risk(tweak.risk))
            Hairline()
            DefinitionRow(label: "Applies", value: TweakCopy.restart(tweak.restart))
            Hairline()
            DefinitionRow(label: "Configuration", value: tweak.configurationLabel, monospaced: true)
            Hairline()
            DefinitionRow(label: "Last change", value: lastChangeText)
        }
    }

    private var lastChangeText: String {
        guard let record = model.lastChange(for: tweak.id) else { return "Never" }
        let when = record.at.formatted(date: .abbreviated, time: .shortened)
        return "\(TweakCopy.action(record.action)), \(when)"
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: Spacing.s3) {
            SecondaryActionButton(
                title: "Reset to Default",
                isEnabled: reading?.isCustomized ?? false,
                help: "Remove this setting and use the macOS default"
            ) {
                model.reset(tweak)
            }
            if let record = model.rollbackTarget(for: tweak.id) {
                QuietActionButton(
                    title: "Revert last change",
                    help: "Put back the value from before the last change"
                ) {
                    model.rollback(record, tweak: tweak)
                }
            }
            Spacer(minLength: Spacing.s3)
            if tweak.restart.processName != nil, model.needsRestart(tweak.id) {
                SecondaryActionButton(title: "Restart \(TweakCopy.processName(tweak.restart))") {
                    model.restart(tweak.restart)
                }
            }
            primaryAction
        }
    }

    @ViewBuilder private var primaryAction: some View {
        if case .toggle = tweak.control {
            if reading?.state == .on {
                PrimaryActionButton(title: "Turn Off") { model.toggle(tweak) }
            } else {
                PrimaryActionButton(title: "Turn On") { model.toggle(tweak) }
            }
        }
    }
}
