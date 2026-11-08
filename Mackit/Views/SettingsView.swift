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

/// The app's Settings page (Cmd+,): what a scan looks at, in the order the scan uses it.
/// Values apply to the next scan, never to one already running.
struct SettingsView: View {
    @Environment(ScanModel.self) private var model
    @State private var newExclusion = ""

    /// Steps the user may switch off. Rules and the folder index always run.
    private let optionalSteps: [ScanStep] = [.largeFiles, .duplicates, .leftovers, .photos, .videos, .snapshots]

    private var enabledStepCount: Int {
        optionalSteps.filter(model.isStepEnabled).count
    }

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s6) {
                PageHeader(
                    title: "Settings",
                    subtitle: "What a scan looks at. Changes apply to the next scan.")

                if DryRun.enabled {
                    StatusLabel(
                        text: "Dry run is on. Cleaning only simulates.",
                        systemImage: "eye.slash",
                        tone: .amber,
                        help: "DRY_RUN is set in the environment or a .env file")
                }

                stepsSection
                scopeSection(model: model)
                excludedSection
                thresholdsSection(model: model)
                speedSection(model: model)
            }
            .padding(.horizontal, Metrics.pageMargin)
            .padding(.vertical, Spacing.s6)
            .frame(maxWidth: 560, alignment: .leading)
        }
        .background(Theme.paper)
        .tint(Theme.accent)
        .frame(width: 560, height: 760)
        .background(SettingsWindowTitle())
    }

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            SectionHeader(title: "Scan steps", trailing: "\(enabledStepCount) of \(optionalSteps.count) on")
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text("Rules and folder index")
                        .font(Typography.body)
                        .foregroundStyle(Theme.ink)
                    Text("Always run: they feed the sidebar and the disk map.")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer(minLength: Spacing.s3)
                StatusLabel(text: "Always on", systemImage: "lock", tone: .neutral)
            }
            Hairline()
            LazyVGrid(
                columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                spacing: Spacing.s2
            ) {
                ForEach(optionalSteps, id: \.rawValue) { step in
                    Toggle(
                        step.title,
                        isOn: Binding(
                            get: { model.isStepEnabled(step) },
                            set: { model.setStep(step, enabled: $0) }))
                    .font(Typography.body)
                    .foregroundStyle(Theme.ink)
                    .accessibilityLabel(step.title)
                    .accessibilityValue(model.isStepEnabled(step) ? "On" : "Off")
                }
            }
        }
    }

    private func scopeSection(model: ScanModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            SectionHeader(title: "Where to look")
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
        }
    }

    private var excludedSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            SectionHeader(
                title: "Excluded folders",
                trailing: model.excludedPaths.isEmpty ? "none" : "\(model.excludedPaths.count) excluded")
            if model.excludedPaths.isEmpty {
                EmptyStateView(
                    title: "Nothing excluded yet",
                    message: "Add a folder below and every scan skips it. Write ~ for your home folder.")
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
            VStack(alignment: .leading, spacing: Spacing.s2) {
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
    }

    private func thresholdsSection(model: ScanModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            SectionHeader(title: "Thresholds")
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

    private func speedSection(model: ScanModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            SectionHeader(title: "Speed")
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
                Text("Folder walk threads")
                    .font(Typography.body)
                    .foregroundStyle(Theme.ink)
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
                .frame(width: 220)
            }
            Text("Auto uses one thread per core. Fewer threads finish slower and keep the fan quiet.")
                .font(Typography.caption)
                .foregroundStyle(Theme.inkSecondary)
        }
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
