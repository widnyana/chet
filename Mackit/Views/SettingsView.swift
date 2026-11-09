import AppKit
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

/// Settings page (Cmd+,). Every value applies to the next scan.
struct SettingsView: View {
    @Environment(ScanModel.self) private var model

    private let optionalSteps: [ScanStep] = [.largeFiles, .duplicates, .leftovers, .photos, .videos, .snapshots]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s6) {
                PageHeader(title: "Settings", subtitle: "Applies to the next scan.")

                if DryRun.enabled {
                    StatusLabel(
                        text: "Dry run on. Cleaning only simulates.",
                        systemImage: "eye.slash",
                        tone: .amber,
                        help: "DRY_RUN is set in the environment or a .env file")
                }

                scanSection
                sizesSection
                excludedSection
                rulesSection
                outsideSection
                threadsFooter
            }
            .padding(.horizontal, Metrics.pageMargin)
            .padding(.vertical, Metrics.pageMargin)
            .frame(maxWidth: 452, alignment: .leading)
        }
        .background(Theme.paper)
        .tint(Theme.accent)
        .frame(width: 500, height: 600)
        .background(SettingsWindowTitle())
    }

    private var scanSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            SectionHeader(title: "What to scan")
            Text("Rules and folder index always run.")
                .font(Typography.caption)
                .foregroundStyle(Theme.inkSecondary)
            VStack(alignment: .leading, spacing: Spacing.s2) {
                ForEach(optionalSteps, id: \.rawValue) { step in
                    Toggle(
                        step.title,
                        isOn: Binding(
                            get: { model.isStepEnabled(step) },
                            set: { model.setStep(step, enabled: $0) }))
                    .font(Typography.body)
                    .foregroundStyle(Theme.ink)
                    .accessibilityLabel(step.title)
                }
            }
        }
    }

    private var sizesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            SectionHeader(title: "Sizes and ages")
            SliderRow(
                title: "Duplicate size",
                valueText: "\(model.duplicateMinSizeMB) MB",
                value: Binding(
                    get: { Double(model.duplicateMinSizeMB) },
                    set: { model.duplicateMinSizeMB = Int($0) }),
                range: 1...100, step: 1)
            Toggle(isOn: Binding(
                get: { model.includeTempInDuplicates },
                set: { model.includeTempInDuplicates = $0 }))
            {
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text("Search caches and build folders")
                        .font(Typography.body)
                        .foregroundStyle(Theme.ink)
                    Text("Off by default.")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .accessibilityLabel("Search caches and build folders")
            Hairline()
            SliderRow(
                title: "Large file size",
                valueText: "\(model.largeFileMinSizeMB) MB",
                value: Binding(
                    get: { Double(model.largeFileMinSizeMB) },
                    set: { model.largeFileMinSizeMB = Int($0) }),
                range: 50...2000, step: 50)
            Hairline()
            SliderRow(
                title: "Old file age",
                valueText: "\(model.largeFileOldAgeDays) days",
                value: Binding(
                    get: { Double(model.largeFileOldAgeDays) },
                    set: { model.largeFileOldAgeDays = Int($0) }),
                range: 30...730, step: 30)
        }
    }

    private var excludedSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            SectionHeader(title: "Excluded folders")
            if model.excludedPaths.isEmpty {
                Text("No folders are excluded.")
                    .font(Typography.body)
                    .foregroundStyle(Theme.inkSecondary)
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
            Button("Choose Folder…") { chooseExcludedFolders() }
                .accessibilityLabel("Choose folder to exclude")
        }
    }

    /// The app is not sandboxed, so the picked path stays readable after relaunch.
    private func chooseExcludedFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Exclude"
        panel.message = "Choose folders every scan skips."
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            model.addExcludedPath(url.path)
        }
    }

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            SectionHeader(title: "Your rules")
            if model.userRules.isEmpty {
                Text("No rules of your own yet.")
                    .font(Typography.body)
                    .foregroundStyle(Theme.inkSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(model.userRules) { userRule in
                        HStack(spacing: Spacing.s2) {
                            Text(userRule.path)
                                .font(Typography.row)
                                .foregroundStyle(Theme.inkSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: Spacing.s2)
                            Button("Remove") { model.removeUserRule(userRule.id) }
                                .buttonStyle(.link)
                                .font(Typography.caption)
                                .accessibilityLabel("Remove rule for \(userRule.path)")
                        }
                        .padding(.vertical, Spacing.s2)
                        Hairline()
                    }
                }
            }
            Button("Add Rule…") { chooseRuleFolders() }
                .accessibilityLabel("Add a rule for a folder")
        }
    }

    private func chooseRuleFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose folders whose contents a scan may reclaim."
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            model.addUserRule(path: url.path)
        }
    }

    private var outsideSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            SectionHeader(title: "Outside your home folder")
            Toggle(isOn: Binding(
                get: { model.scanOutsideHome },
                set: { model.scanOutsideHome = $0 }))
            {
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text("Read folders outside your home folder")
                        .font(Typography.body)
                        .foregroundStyle(Theme.ink)
                    Text("For machines or projects kept on another disk.")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .accessibilityLabel("Read folders outside your home folder")
        }
    }

    private var threadsFooter: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Hairline()
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
                Text("Threads")
                    .font(Typography.row)
                    .foregroundStyle(Theme.inkSecondary)
                Spacer(minLength: Spacing.s3)
                Picker("Threads", selection: Binding(
                    get: { model.scanThreads },
                    set: { model.scanThreads = $0 }))
                {
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
            Text("Auto uses one thread per core.")
                .font(Typography.caption)
                .foregroundStyle(Theme.inkSecondary)
        }
    }
}

/// Label and value on one line, so the number and the thumb cannot disagree.
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
