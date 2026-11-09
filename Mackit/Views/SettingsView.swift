import AppKit
import MackitCore
import SwiftUI

/// Settings page (Cmd+,). Three tabs, one question each: what the scan looks at, how it
/// measures sizes, and which folders it reads. Every value applies to the next scan.
/// The window title follows the active pane, the standard macOS preference-pane behavior.
struct SettingsView: View {
    @Environment(ScanModel.self) private var model

    private let optionalSteps: [ScanStep] = [.largeFiles, .duplicates, .leftovers, .photos, .videos, .snapshots]

    var body: some View {
        VStack(spacing: 0) {
            if DryRun.enabled {
                StatusLabel(
                    text: "Dry run on. Cleaning only simulates.",
                    systemImage: "eye.slash",
                    tone: .amber)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Metrics.pageMargin)
                    .padding(.top, Spacing.s3)
            }
            TabView {
                scanTab.tabItem { Text("Scan") }
                sizesTab.tabItem { Text("Sizes") }
                foldersTab.tabItem { Text("Folders") }
            }
        }
        .background(Theme.paper)
        .tint(Theme.accent)
        .frame(width: 500, height: 520)
    }

    /// One scrolling column per tab, with the page margins applied once.
    private func page<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s6) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Metrics.pageMargin)
        }
    }

    private var scanTab: some View {
        page {
            VStack(alignment: .leading, spacing: Spacing.s3) {
                SectionHeader(title: "Steps")
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
            threadsSection
        }
    }

    private var sizesTab: some View {
        page {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                SectionHeader(title: "Sizes and ages")
                SliderRow(
                    title: "Duplicate size",
                    valueText: "\(model.duplicateMinSizeMB) MB",
                    value: Binding(
                        get: { Double(model.duplicateMinSizeMB) },
                        set: { model.duplicateMinSizeMB = Int($0) }),
                    range: 1...100, step: 1)
                Toggle("Search caches and build folders", isOn: Binding(
                    get: { model.includeTempInDuplicates },
                    set: { model.includeTempInDuplicates = $0 }))
                .font(Typography.body)
                .foregroundStyle(Theme.ink)
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
    }

    private var foldersTab: some View {
        page {
            excludedSection
            rulesSection
            outsideSection
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
                                .buttonStyle(.borderless)
                                .font(Typography.caption)
                                .foregroundStyle(Theme.inkSecondary)
                                .accessibilityLabel("Stop excluding \(path)")
                        }
                        .padding(.vertical, Spacing.s2)
                        Hairline()
                    }
                }
            }
            Button("Exclude Folder…") { chooseExcludedFolders() }
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
            Text("Children of an added folder are listed as Your folders, reviewed, and moved to Trash.")
                .font(Typography.caption)
                .foregroundStyle(Theme.inkSecondary)
            if model.userRules.isEmpty {
                Text("No folder rules yet.")
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
                                .buttonStyle(.borderless)
                                .font(Typography.caption)
                                .foregroundStyle(Theme.inkSecondary)
                                .accessibilityLabel("Remove rule for \(userRule.path)")
                        }
                        .padding(.vertical, Spacing.s2)
                        Hairline()
                    }
                }
            }
            Button("Add Folder Rule…") { chooseRuleFolders() }
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

    private var threadsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            SectionHeader(title: "Speed")
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
                Text("Threads")
                    .font(Typography.body)
                    .foregroundStyle(Theme.ink)
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
                .pickerStyle(.menu)
                .fixedSize()
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
