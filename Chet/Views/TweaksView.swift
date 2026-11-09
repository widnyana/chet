import AppKit
import ChetCore
import SwiftUI

/// The tweaks destination: one preference list grouped by the part of macOS it changes.
/// A row states its current value and offers the one control that changes it. Details,
/// risk, and the recorded change live in the sheet.
struct TweaksView: View {
    @Environment(TweaksModel.self) private var model
    @State private var detail: Tweak?

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s6) {
                PageHeader(
                    title: "Tweaks",
                    subtitle:
                        "Change how macOS behaves. Every change is recorded and can be reverted."
                )
                .accessibilityIdentifier("tweaks.header")
                toolbar
                notice
                content
            }
            .padding(.horizontal, Metrics.widePageMargin)
            .padding(.vertical, Spacing.s8)
            .frame(maxWidth: Metrics.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Theme.paper)
        .searchable(text: $model.query, placement: .toolbar, prompt: "Search tweaks")
        .task {
            if model.readings.isEmpty { await model.load() }
        }
        .sheet(item: $detail) { tweak in
            TweakDetailView(tweak: tweak)
        }
        .accessibilityIdentifier("tweaks.page")
    }

    private var toolbar: some View {
        @Bindable var model = model
        return HStack(spacing: Spacing.s3) {
            Picker("Show", selection: $model.filter) {
                ForEach(TweakFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Text(summary)
                .font(Typography.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.inkSecondary)
            Spacer()
            QuietActionButton(
                title: "Read again", help: "Read every value from macOS again"
            ) {
                Task { await model.reload() }
            }
            .accessibilityIdentifier("tweaks.reload")
        }
    }

    private var summary: String {
        let shown = model.matchingCategories.reduce(0) { $0 + model.tweaks(in: $1).count }
        return shown == 1 ? "1 tweak" : "\(shown) tweaks"
    }

    @ViewBuilder private var notice: some View {
        if model.isGated {
            StatusLabel(
                text: "Preview only. No tweak is changed.", systemImage: "eye.slash", tone: .amber)
        }
        if let message = model.errorMessage {
            HStack(spacing: Spacing.s3) {
                StatusLabel(
                    text: message, systemImage: "exclamationmark.triangle", tone: .red)
                Spacer(minLength: Spacing.s3)
                QuietActionButton(title: "Dismiss") { model.dismissError() }
            }
        }
        ForEach(pendingRestarts, id: \.self) { target in
            HStack(spacing: Spacing.s3) {
                StatusLabel(
                    text: TweakCopy.restart(target), systemImage: "arrow.clockwise", tone: .amber)
                Spacer(minLength: Spacing.s3)
                if target.processName != nil {
                    SecondaryActionButton(title: "Restart \(TweakCopy.processName(target))") {
                        model.restart(target)
                    }
                }
            }
        }
    }

    private var pendingRestarts: [TweakRestart] {
        model.pendingRestartTargets
    }

    @ViewBuilder private var content: some View {
        if model.isLoading {
            LoadingStateView(message: "Reading your settings.")
                .accessibilityIdentifier("tweaks.loading")
        } else if !model.hasAnyMatch {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: Spacing.s6) {
                ForEach(model.matchingCategories, id: \.self) { category in
                    section(category)
                }
                Text(
                    "Each change is checked by reading the value back. A failed change restores the earlier value."
                )
                .font(Typography.caption)
                .foregroundStyle(Theme.inkSecondary)
            }
        }
    }

    private func section(_ category: TweakCategory) -> some View {
        let rows = model.tweaks(in: category)
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: category.title, trailing: "\(rows.count)")
            ForEach(rows) { reading in
                TweakRow(reading: reading) { detail = reading.tweak }
                if reading.id != rows.last?.id { Hairline() }
            }
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            title: model.filter == .changed && model.query.isEmpty ? "No changed tweaks" : "No tweaks match",
            message: emptyMessage,
            systemImage: "slider.horizontal.3",
            actionTitle: "Show all tweaks",
            action: {
                model.query = ""
                model.filter = .all
            }
        )
        .accessibilityIdentifier("tweaks.empty")
    }

    private var emptyMessage: String {
        if model.filter == .changed && model.query.isEmpty {
            return "Every supported setting still has its macOS default."
        }
        return "Try another word, or show all tweaks."
    }
}

/// One preference row. The control reads its value from the model, so a failed write puts
/// the row back where it was.
private struct TweakRow: View {
    @Environment(TweaksModel.self) private var model
    let reading: TweakReading
    let onDetails: () -> Void

    var body: some View {
        PreferenceRow(
            title: reading.tweak.name,
            detail: reading.tweak.summary,
            state: stateLine,
            notes: notes,
            isEnabled: !model.isGated,
            onDetails: onDetails
        ) {
            control
        }
    }

    private var notes: [PreferenceNote] {
        var notes: [PreferenceNote] = []
        if reading.tweak.risk > .low {
            notes.append(
                PreferenceNote(
                    TweakCopy.risk(reading.tweak.risk), systemImage: "shield.lefthalf.filled",
                    tone: TweakCopy.riskTone(reading.tweak.risk)))
        }
        if reading.tweak.restart != .none, model.needsRestart(reading.id) {
            notes.append(
                PreferenceNote(restartLine, systemImage: "arrow.clockwise", tone: .amber))
        }
        return notes
    }

    private var stateLine: String {
        switch reading.state {
        case .unsupported, .unknown:
            return TweakCopy.state(reading.state)
        default:
            return "\(TweakCopy.state(reading.state)) · \(reading.tweak.impact)"
        }
    }

    private var restartLine: String {
        reading.tweak.restart == .login
            ? "Sign in again" : "Restart \(TweakCopy.processName(reading.tweak.restart))"
    }

    @ViewBuilder private var control: some View {
        if model.busy.contains(reading.id) {
            ProgressView()
                .controlSize(.small)
        } else {
            switch reading.tweak.control {
            case .toggle:
                Toggle(
                    reading.tweak.name,
                    isOn: Binding(
                        get: { reading.state == .on },
                        set: { _ in model.toggle(reading.tweak) })
                )
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(!reading.isSupported)
                .accessibilityIdentifier("tweak.toggle.\(reading.id)")
            case .choice(let options):
                Picker(
                    reading.tweak.name,
                    selection: Binding(
                        get: { reading.current ?? reading.tweak.defaultValue },
                        set: { value in
                            guard let value else { return }
                            model.set(reading.tweak, to: value)
                        })
                ) {
                    ForEach(options, id: \.self) { option in
                        Text(option.label).tag(Optional(option.value))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .disabled(!reading.isSupported)
                .accessibilityIdentifier("tweak.choice.\(reading.id)")
            case .folder:
                HStack(spacing: Spacing.s2) {
                    Text(TweakCopy.state(reading.state))
                        .font(Typography.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    QuietActionButton(title: "Choose…") { chooseFolder() }
                        .disabled(!reading.isSupported)
                        .accessibilityIdentifier("tweak.folder.\(reading.id)")
                }
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Use This Folder"
        panel.message = "Choose where new screenshots are saved."
        if case .string(let path) = reading.current ?? reading.tweak.defaultValue {
            panel.directoryURL = URL(fileURLWithPath: path)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.set(reading.tweak, to: .string(url.path))
    }
}
