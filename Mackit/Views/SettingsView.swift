import MackitCore
import SwiftUI

/// SwiftUI's `Settings` scene titles its window "<AppName> Settings" and offers no
/// title modifier. The design language wants the plain word, so the hosting window's
/// title is fixed when the view lands in it.
struct SettingsWindowTitle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { view.window?.title = "Settings" }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { view.window?.title = "Settings" }
    }
}

/// The app's Settings page (Cmd+,). It is a board for the next scan: each switch sits next to
/// what that step found last time, so a step is never just a name. Values apply to the next
/// scan, never to one already running.
struct SettingsView: View {
    @Environment(ScanModel.self) private var model
    @State private var newExclusion = ""

    /// Steps the user may switch off. Rules and the folder index always run.
    private let optionalSteps: [ScanStep] = [.largeFiles, .duplicates, .leftovers, .photos, .videos, .snapshots]
    /// Category ids that are not produced by the rules step.
    private let nonRuleCategories: Set<String> = [
        "duplicates", "large-files", "leftovers", "similar-photos", "blurry-photos", "similar-videos",
        "tagged-caches", "snapshots",
    ]

    private var enabledStepCount: Int {
        optionalSteps.filter(model.isStepEnabled).count
    }

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s6) {
                header

                if DryRun.enabled {
                    StatusLabel(
                        text: "Dry run is on. Cleaning only simulates.",
                        systemImage: "eye.slash",
                        tone: .amber,
                        help: "DRY_RUN is set in the environment or a .env file")
                }

                stepsLedger
                limitsSection(model: model)
                keepOutSection(model: model)
                speedFooter(model: model)
            }
            .padding(.horizontal, Metrics.pageMargin)
            .padding(.vertical, Spacing.s6)
            .frame(maxWidth: 600, alignment: .leading)
        }
        .background(Theme.paper)
        .tint(Theme.accent)
        .frame(width: 600, height: 680)
        .background(SettingsWindowTitle())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            PageHeader(
                title: "Settings",
                subtitle: "What the next scan looks at. Nothing here changes a scan already running.")
            HStack(spacing: Spacing.s2) {
                Text("\(enabledStepCount) of \(optionalSteps.count) steps on")
                    .font(Typography.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.inkSecondary)
                Text("·")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.inkTertiary)
                Text(lastScanLine)
                    .font(Typography.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
    }

    private var lastScanLine: String {
        if model.isScanning { return "scanning now" }
        guard let date = model.lastScan else { return "no scan yet" }
        return "last scan \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    private var stepsLedger: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Steps", trailing: "found last scan")
            HStack(spacing: Spacing.s3) {
                Text("Step")
                Spacer(minLength: Spacing.s3)
                Text("Found")
                    .frame(width: 150, alignment: .trailing)
                Text("On")
                    .frame(width: 90, alignment: .trailing)
            }
            .font(Typography.caption)
            .foregroundStyle(Theme.inkSecondary)
            .padding(.top, Spacing.s2)
            .padding(.bottom, Spacing.s1)

            StepLedgerRow(title: "Rules and folder index", found: rulesFoundText, locked: true, isOn: .constant(true))
            Hairline()

            ForEach(optionalSteps, id: \.rawValue) { step in
                StepLedgerRow(
                    title: step.title,
                    found: foundText(for: step),
                    locked: false,
                    isOn: Binding(
                        get: { model.isStepEnabled(step) },
                        set: { model.setStep(step, enabled: $0) }))
                Hairline()
            }
        }
    }

    /// What the rules step found last scan. Rules always run, so this is the only evidence the
    /// locked row can show.
    private var rulesFoundText: String {
        if model.isScanning { return "running" }
        guard model.lastScan != nil else { return "not run" }
        let count = model.categories.filter { !nonRuleCategories.contains($0.id) }.reduce(0) { $0 + $1.items.count }
        return "\(count) items"
    }

    /// What one optional step found last scan. A step switched off says `off`, not a stale or
    /// zero count; a scan that has not run says `not run`, never a zero standing in for a value.
    private func foundText(for step: ScanStep) -> String {
        guard model.isStepEnabled(step) else { return "off" }
        if model.isScanning { return "running" }
        guard model.lastScan != nil else { return "not run" }
        switch step {
        case .rules, .index:
            return "always on"
        case .largeFiles:
            return countText(category: "large-files", noun: "files")
        case .duplicates:
            return groupText(["duplicates"], noun: "groups")
        case .leftovers:
            return countText(category: "leftovers", noun: "folders")
        case .photos:
            let clusters = model.groups["similar-photos"]?.count ?? 0
            let blurry = model.categories.first { $0.id == "blurry-photos" }?.items.count ?? 0
            if blurry == 0 { return "\(clusters) groups" }
            if clusters == 0 { return "\(blurry) blurry" }
            return "\(clusters) groups · \(blurry) blurry"
        case .videos:
            return groupText(["similar-videos"], noun: "groups")
        case .snapshots:
            return "\(model.snapshots.count) snapshots"
        }
    }

    private func countText(category: String, noun: String) -> String {
        let count = model.categories.first { $0.id == category }?.items.count ?? 0
        return "\(count) \(noun)"
    }

    private func groupText(_ ids: [String], noun: String) -> String {
        let count = ids.reduce(0) { $0 + (model.groups[$1]?.count ?? 0) }
        return "\(count) \(noun)"
    }

    private func limitsSection(model: ScanModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            SectionHeader(title: "Limits")
            SliderRow(
                title: "Duplicate files at least",
                valueText: "\(model.duplicateMinSizeMB) MB",
                value: Binding(get: { Double(model.duplicateMinSizeMB) }, set: { model.duplicateMinSizeMB = Int($0) }),
                range: 1...100, step: 1)
            Hairline()
            SliderRow(
                title: "Large files at least",
                valueText: "\(model.largeFileMinSizeMB) MB",
                value: Binding(get: { Double(model.largeFileMinSizeMB) }, set: { model.largeFileMinSizeMB = Int($0) }),
                range: 50...2000, step: 50)
            Hairline()
            SliderRow(
                title: "Old after",
                valueText: "\(model.largeFileOldAgeDays) days",
                value: Binding(get: { Double(model.largeFileOldAgeDays) }, set: { model.largeFileOldAgeDays = Int($0) }),
                range: 30...730, step: 30)
        }
    }

    private func keepOutSection(model: ScanModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            SectionHeader(
                title: "Keep out",
                trailing: model.excludedPaths.isEmpty ? "none excluded" : "\(model.excludedPaths.count) excluded")
            Toggle(isOn: Binding(get: { model.scanOutsideHome }, set: { model.scanOutsideHome = $0 })) {
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text("Read folders outside your home folder")
                        .font(Typography.body)
                        .foregroundStyle(Theme.ink)
                    Text("For VirtualBox machines or projects kept on another disk. Off by default.")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .accessibilityLabel("Read folders outside your home folder")
            .accessibilityValue(model.scanOutsideHome ? "On" : "Off")
            Hairline()

            if model.excludedPaths.isEmpty {
                Text("Nothing excluded. Add a folder below and every scan skips it.")
                    .font(Typography.body)
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.vertical, Spacing.s2)
            } else {
                VStack(spacing: 0) {
                    ForEach(model.excludedPaths, id: \.self) { path in
                        HStack(spacing: Spacing.s2) {
                            Text(path)
                                .font(Typography.row)
                                .foregroundStyle(Theme.inkSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: Spacing.s2)
                            Button("Remove") { model.removeExcludedPath(path) }
                                .buttonStyle(.link)
                                .font(Typography.caption)
                                .accessibilityLabel("Stop excluding \(path)")
                        }
                        .padding(.vertical, Spacing.s2)
                        Hairline()
                    }
                }
            }

            HStack(spacing: Spacing.s2) {
                TextField("~/Downloads/keep", text: $newExclusion)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Folder to exclude")
                Button("Add") {
                    if model.addExcludedPath(newExclusion) { newExclusion = "" }
                }
                .disabled(newExclusion.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Add excluded folder")
            }
            if !newExclusion.isEmpty, ScanModel.normalizedPath(newExclusion) == nil {
                StatusLabel(
                    text: "Write ~/folder or /folder. A relative path excludes nothing.",
                    systemImage: "exclamationmark.circle",
                    tone: .red)
            }
        }
    }

    private func speedFooter(model: ScanModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Hairline()
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
                Text("Folder walk threads")
                    .font(Typography.row)
                    .foregroundStyle(Theme.inkSecondary)
                Spacer(minLength: Spacing.s3)
                Picker("Folder walk threads", selection: Binding(get: { model.scanThreads }, set: { model.scanThreads = $0 })) {
                    Text("Auto").tag(0)
                    Text("1").tag(1)
                    Text("2").tag(2)
                    Text("4").tag(4)
                    Text("8").tag(8)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            Text("Auto uses one thread per core. Fewer threads finish slower and keep the fan quiet.")
                .font(Typography.caption)
                .foregroundStyle(Theme.inkSecondary)
        }
    }
}

/// One step in the ledger: name, what it found last scan, and its switch or the locked label.
private struct StepLedgerRow: View {
    let title: String
    let found: String
    let locked: Bool
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
            Text(title)
                .font(Typography.body)
                .foregroundStyle(Theme.ink)
            Spacer(minLength: Spacing.s3)
            Text(found)
                .font(Typography.row)
                .monospacedDigit()
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
                .frame(width: 150, alignment: .trailing)
            if locked {
                StatusLabel(text: "Always on", systemImage: "lock", tone: .neutral)
                    .frame(width: 90, alignment: .trailing)
            } else {
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .frame(width: 90, alignment: .trailing)
                    .accessibilityLabel(title)
                    .accessibilityValue(isOn ? "On" : "Off")
            }
        }
        .padding(.vertical, Spacing.s2)
    }
}

/// A labelled slider with its value on the same line, so the number and the control cannot
/// disagree. The value is tabular: it does not shift while the thumb moves.
private struct SliderRow: View {
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
                Text(title)
                    .font(Typography.body)
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: Spacing.s3)
                Text(valueText)
                    .font(Typography.metric)
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
            }
            Slider(value: $value, in: range, step: step)
                .controlSize(.small)
                .accessibilityLabel(title)
                .accessibilityValue(valueText)
        }
        .padding(.vertical, Spacing.s2)
    }
}
