import AppKit
import ChetCore
import SwiftUI

/// One tweak in full: what it changes, its current value, the preference key behind it,
/// and the actions that change or revert it. The row keeps the fast control; this sheet
/// carries the consequence.
struct TweakDetailView: View {
    @Environment(TweaksModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let tweak: Tweak
    @State private var revertRecord: TweakRecord?

    private var reading: TweakReading? { model.reading(for: tweak.id) }
    private var isSupported: Bool { reading?.isSupported == true }

    private var isInspection: Bool {
        if case .probe = tweak.target { return true }
        return false
    }

    private var probeURL: URL? {
        if case .probe(let probe) = tweak.target { return probe.settingsURL }
        return nil
    }

    var body: some View {
        SheetFrame(width: Metrics.detailSheetWidth) {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                header
                Hairline()
                Text(tweak.detail)
                    .font(Typography.body)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if model.isGated {
                    PreviewNotice(text: PreviewCopy.tweaks, tone: .inert)
                }
                if !isSupported, let reading {
                    StatusLabel(
                        text: TweakCopy.state(reading.state),
                        systemImage: "questionmark.circle",
                        tone: .neutral)
                }
                facts
                actions
                    .disabled(model.isGated || !isSupported)
            }
        }
        .accessibilityIdentifier("tweak.detail.\(tweak.id)")
        .confirmationDialog(
            "Revert the last change?",
            isPresented: Binding(
                get: { revertRecord != nil },
                set: { if !$0 { revertRecord = nil } }),
            titleVisibility: .visible,
            presenting: revertRecord
        ) { record in
            Button("Revert") {
                model.rollback(record, tweak: tweak)
                revertRecord = nil
            }
            Button("Cancel", role: .cancel) { revertRecord = nil }
        } message: { record in
            Text("Puts \(TweakCopy.value(record.before)) back for \(tweak.name).")
        }
        #if DEBUG
            .onAppear {
                guard ProcessInfo.processInfo.environment["CHET_TWEAK_PREVIEW"] == "revert" else {
                    return
                }
                revertRecord = TweakRecord(
                    tweakID: tweak.id, action: .set, before: tweak.defaultValue, after: nil)
            }
        #endif
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
            DefinitionRow(
                label: isInspection ? "Checked by" : "Configuration",
                value: tweak.configurationLabel, monospaced: true)
            ForEach(Array(tweak.companions.enumerated()), id: \.offset) { _, target in
                Hairline()
                DefinitionRow(label: "Also writes", value: target.configurationLabel, monospaced: true)
            }
            Hairline()
            DefinitionRow(label: "Last change", value: lastChangeText)
            if isInspection {
                Hairline()
                DefinitionRow(
                    label: "Note",
                    value: "Chet only reads this. A change is made in System Settings.")
            }
        }
    }

    private var lastChangeText: String {
        guard let record = model.lastChange(for: tweak.id) else { return "Never" }
        let when = record.at.formatted(date: .abbreviated, time: .shortened)
        return "\(TweakCopy.action(record.action)), \(when)"
    }

    @ViewBuilder private var actions: some View {
        if isInspection {
            HStack {
                if let probeURL {
                    SecondaryActionButton(
                        title: "Open Settings",
                        help: "Open the System Settings pane for \(tweak.name)"
                    ) {
                        NSWorkspace.shared.open(probeURL)
                    }
                }
                Spacer(minLength: Spacing.s3)
            }
        } else {
            editActions
        }
    }

    @ViewBuilder private var editActions: some View {
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
                    revertRecord = record
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
        if isSupported, case .toggle = tweak.control {
            if reading?.state == .on {
                PrimaryActionButton(title: "Turn Off") { model.toggle(tweak) }
            } else {
                PrimaryActionButton(title: "Turn On") { model.toggle(tweak) }
            }
        }
    }
}
