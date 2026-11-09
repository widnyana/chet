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
        .sheet(item: $model.pendingConfirmation) { pending in
            TweakConfirmView(pending: pending)
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
                    SecondaryActionButton(title: "Restart \(TweakCopy.processName(target))", isEnabled: !model.isGated) {
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
        if let failure = model.failure(for: reading.id) {
            notes.append(
                PreferenceNote(
                    "Could not change", systemImage: "xmark.octagon", tone: .red,
                    help: failure))
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
            case .range:
                TweakRangeControl(reading: reading)
            case .text(let placeholder):
                TweakTextControl(reading: reading, placeholder: placeholder)
            case .inspect:
                if let url = settingsURL {
                    SecondaryActionButton(
                        title: "Open Settings",
                        help: "Open the System Settings pane for \(reading.tweak.name)"
                    ) {
                        NSWorkspace.shared.open(url)
                    }
                    .accessibilityIdentifier("tweak.inspect.\(reading.id)")
                }
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

    private var settingsURL: URL? {
        if case .probe(let probe) = reading.tweak.target { return probe.settingsURL }
        return nil
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

/// A numeric preference. The write happens once, when the drag ends, so a slider gesture
/// does not produce one write per tick.
private struct TweakRangeControl: View {
    @Environment(TweaksModel.self) private var model
    let reading: TweakReading
    @State private var value: Double = 0

    private var range: ClosedRange<Double> {
        if case .range(let minimum, let maximum, _, _) = reading.tweak.control {
            return minimum...maximum
        }
        return 0...1
    }

    private var step: Double {
        if case .range(_, _, let step, _) = reading.tweak.control { return step }
        return 1
    }

    private var unit: String? {
        if case .range(_, _, _, let unit) = reading.tweak.control { return unit }
        return nil
    }

    private var current: Double {
        switch reading.current ?? reading.tweak.defaultValue {
        case .integer(let number): Double(number)
        case .number(let number): number
        default: range.lowerBound
        }
    }

    private var readout: String {
        let base = step >= 1 ? String(Int(value.rounded())) : String(format: "%.1f", value)
        return unit.map { "\(base) \($0)" } ?? base
    }

    var body: some View {
        HStack(spacing: Spacing.s2) {
            Slider(value: $value, in: range, step: step) { editing in
                if !editing { commit() }
            }
            .controlSize(.small)
            .accessibilityIdentifier("tweak.range.\(reading.id)")
            Text(readout)
                .font(Typography.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.inkSecondary)
                .frame(width: 58, alignment: .trailing)
        }
        .onAppear { value = current }
        .onChange(of: reading.current) { _, _ in value = current }
        .disabled(!reading.isSupported || model.isGated)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(reading.tweak.name)
        .accessibilityValue(readout)
    }

    private func commit() {
        guard !model.isGated, reading.isSupported else { return }
        if case .defaults(_, _, let type) = reading.tweak.target, type == .integer {
            model.set(reading.tweak, to: .integer(Int(value.rounded())))
        } else {
            model.set(reading.tweak, to: .number(value))
        }
    }
}

/// A free-text preference. Committed on Return or when focus leaves the field. Clearing
/// the field removes the key, which restores the macOS default.
private struct TweakTextControl: View {
    @Environment(TweaksModel.self) private var model
    let reading: TweakReading
    let placeholder: String
    @State private var text = ""
    @FocusState private var focused: Bool

    private var stored: String {
        if case .string(let value) = reading.current ?? reading.tweak.defaultValue { return value }
        return ""
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
            .font(Typography.caption)
            .focused($focused)
            .onSubmit(commit)
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commit() }
            }
            .onAppear { text = stored }
            .onChange(of: reading.current) { _, _ in text = stored }
            .disabled(!reading.isSupported || model.isGated)
            .accessibilityIdentifier("tweak.text.\(reading.id)")
            .accessibilityLabel(reading.tweak.name)
    }

    private func commit() {
        guard !model.isGated, reading.isSupported else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if reading.isCustomized { model.reset(reading.tweak) }
            return
        }
        if trimmed == stored, reading.isCustomized { return }
        model.set(reading.tweak, to: .string(trimmed))
    }
}
