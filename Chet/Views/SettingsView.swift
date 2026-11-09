import AppKit
import ChetCore
import SwiftUI

/// SwiftUI's `Settings` scene puts the pane buttons in the window toolbar and repeats the
/// active pane name in the title bar. The toolbar already names the pane, so the title text
/// is hidden; the window keeps its title for accessibility and the Window menu.
struct SettingsWindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.titleVisibility = .hidden
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            view.window?.titleVisibility = .hidden
        }
    }
}

/// Settings page (Cmd+,). Three panes, the macOS preference arrangement: a toolbar pane
/// switcher, then grouped panels with the label on the left and its control on the right.
/// The words are for someone who has never opened a terminal. Every value applies to the
/// next scan.
struct SettingsView: View {
    @Environment(ScanModel.self) private var model

    private let optionalSteps: [ScanStep] = [.largeFiles, .duplicates, .leftovers, .photos, .videos, .snapshots]

    var body: some View {
        VStack(spacing: 0) {
            if DryRun.enabled {
                StatusLabel(
                    text: "Preview only. Nothing will be removed.",
                    systemImage: "eye.slash",
                    tone: .amber)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Metrics.pageMargin)
                    .padding(.vertical, Spacing.s2)
                    .background(Theme.paperRaised)
            }
            TabView {
                scanPane.tabItem { Label("What to find", systemImage: "magnifyingglass") }
                sizesPane.tabItem { Label("Limits", systemImage: "ruler") }
                foldersPane.tabItem { Label("Folders", systemImage: "folder") }
            }
            .accessibilityIdentifier("settings.tabs")
        }
        .background(Theme.paper)
        .tint(Theme.accent)
        .frame(width: 560, height: 560)
        .background(SettingsWindowChrome())
    }

    private func pane<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                Text("Changes apply to the next scan.")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.inkSecondary)
                content()
            }
            .padding(Spacing.s4)
        }
    }

    // MARK: - Scan

    private var scanPane: some View {
        pane {
            SettingsPanel(title: "What to look for") {
                SettingsNote("Chet always checks the usual places and measures your folders.")
                ForEach(optionalSteps, id: \.rawValue) { step in
                    let copy = optionalCopy(step)
                    SettingsDivider()
                    SettingsRow(label: copy.title, detail: copy.detail) {
                        Toggle("", isOn: Binding(
                            get: { model.isStepEnabled(step) },
                            set: { model.setStep(step, enabled: $0) }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .accessibilityLabel(copy.title)
                    }
                }
            }
            SettingsPanel(title: "Speed") {
                SettingsRow(label: "Threads", detail: "Auto uses one thread per core.") {
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
                }
            }
        }
    }

    private func optionalCopy(_ step: ScanStep) -> (title: String, detail: String) {
        switch step {
        case .largeFiles: ("Big files", "Files you may not need, including old ones.")
        case .duplicates: ("Duplicate files", "Files with identical contents.")
        case .leftovers: ("Files from removed apps", "Data left after an app was deleted.")
        case .photos: ("Similar photos", "Copies and near-copies of the same photo.")
        case .videos: ("Similar videos", "Re-encoded copies of the same video.")
        case .snapshots: ("Time Machine snapshots", "Local copies Time Machine keeps on this disk.")
        case .rules, .index: (ScanStepCopy.title(step), "")
        }
    }

    // MARK: - Sizes
    private var sizesPane: some View {
        pane {
            SettingsPanel(title: "Duplicate files") {
                SettingsNote("Copies smaller than this are left alone.")
                SettingsDivider()
                sliderRow(
                    title: "Smallest file to compare", value: "\(model.duplicateMinSizeMB) MB",
                    binding: Binding(
                        get: { Double(model.duplicateMinSizeMB) },
                        set: { model.duplicateMinSizeMB = Int($0) }),
                    range: 1...100, step: 1)
                SettingsDivider()
                SettingsRow(
                    label: "Look inside temporary app files",
                    detail: "Apps rebuild them when they need them."
                ) {
                    Toggle("", isOn: Binding(
                        get: { model.includeTempInDuplicates },
                        set: { model.includeTempInDuplicates = $0 }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .accessibilityLabel("Look inside temporary app files")
                }
            }
            SettingsPanel(title: "Big files") {
                SettingsNote("Files this big are listed even if you used them today.")
                SettingsDivider()
                sliderRow(
                    title: "Big file size", value: "\(model.largeFileMinSizeMB) MB",
                    binding: Binding(
                        get: { Double(model.largeFileMinSizeMB) },
                        set: { model.largeFileMinSizeMB = Int($0) }),
                    range: 50...2000, step: 50)
            }
            SettingsPanel(title: "Old files") {
                SettingsNote("Files you have not used for this long are listed.")
                SettingsDivider()
                sliderRow(
                    title: "Unchanged for", value: "\(model.largeFileOldAgeDays) days",
                    binding: Binding(
                        get: { Double(model.largeFileOldAgeDays) },
                        set: { model.largeFileOldAgeDays = Int($0) }),
                    range: 30...730, step: 30)
            }
        }
    }

    private func sliderRow(
        title: String, value: String, binding: Binding<Double>, range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        SettingsRow(label: title) {
            HStack(spacing: Spacing.s2) {
                Slider(value: binding, in: range, step: step)
                    .frame(maxWidth: .infinity)
                    .controlSize(.small)
                    .accessibilityLabel(title)
                    .accessibilityValue(value)
                Text(value)
                    .font(Typography.row)
                    .monospacedDigit()
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(width: 64, alignment: .trailing)
            }
        }
    }

    // MARK: - Folders

    private var foldersPane: some View {
        pane {
            SettingsPanel(title: "Folders Chet should not touch") {
                SettingsNote("Chet never looks inside these and never removes them.")
                if model.excludedPaths.isEmpty {
                    SettingsNote("No folders are skipped.")
                } else {
                    ForEach(model.excludedPaths, id: \.self) { path in
                        SettingsDivider()
                        SettingsRow(label: path) {
                            SecondaryActionButton(
                                title: "Stop skipping",
                                accessibilityLabel: "Stop skipping \(path)",
                                action: { model.removeExcludedPath(path) })
                        }
                    }
                }
                SettingsDivider()
                SettingsActionRow {
                    SecondaryActionButton(
                        title: "Skip a Folder…",
                        accessibilityLabel: "Choose a folder to skip",
                        action: { chooseExcludedFolders() })
                }
            }
            SettingsPanel(title: "Folders you want checked") {
                SettingsNote("Chet lists what is inside. You choose what to remove.")
                if model.userRules.isEmpty {
                    SettingsNote("No folders added yet.")
                } else {
                    ForEach(model.userRules) { userRule in
                        SettingsDivider()
                        SettingsRow(
                            label: userRule.path,
                            detail: userRule.keepNames.isEmpty ? nil : keepDetail(userRule.keepNames)
                        ) {
                            HStack(spacing: Spacing.s2) {
                                SecondaryActionButton(
                                    title: "Keep…",
                                    accessibilityLabel: "Choose items to keep in \(userRule.path)",
                                    action: { chooseKeepItems(for: userRule) })
                                SecondaryActionButton(
                                    title: "Stop checking",
                                    accessibilityLabel: "Stop checking \(userRule.path)",
                                    action: { model.removeUserRule(userRule.id) })
                            }
                        }
                    }
                }
                SettingsDivider()
                SettingsActionRow {
                    SecondaryActionButton(
                        title: "Add a Folder…",
                        accessibilityLabel: "Add a folder to check",
                        action: { chooseRuleFolders() })
                }
            }
            SettingsPanel(title: "Other disks") {
                SettingsRow(
                    label: "Also look on other disks",
                    detail: "For files kept on an external disk."
                ) {
                    Toggle("", isOn: Binding(
                        get: { model.scanOutsideHome },
                        set: { model.scanOutsideHome = $0 }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .accessibilityLabel("Also look on other disks")
                }
            }
        }
    }

    // MARK: - Pickers

    /// The app is not sandboxed, so the picked path stays readable after relaunch.
    private func chooseExcludedFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Skip"
        panel.message = "Choose folders Chet should never look inside."
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            model.addExcludedPath(url.path)
        }
    }

    private func chooseRuleFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose folders Chet should check for files you can remove."
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            model.addUserRule(path: url.path)
        }
    }

    private func keepDetail(_ names: [String]) -> String {
        names.count == 1 ? "Keeping 1 item" : "Keeping \(names.count) items"
    }

    /// Adds items the user picks inside this folder to its keep list. Only direct children are
    /// matched by name, which is what the scanner compares against. Picking is add-only; to
    /// clear the list, remove the folder and add it again.
    private func chooseKeepItems(for userRule: UserRule) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Keep"
        panel.message = "Choose items inside this folder Chet must never remove."
        panel.directoryURL = URL(fileURLWithPath: userRule.path)
        guard panel.runModal() == .OK else { return }
        let parent = URL(fileURLWithPath: userRule.path).standardizedFileURL.path
        var names = userRule.keepNames
        for url in panel.urls
        where url.deletingLastPathComponent().standardizedFileURL.path == parent {
            let name = url.lastPathComponent
            if !names.contains(name) { names.append(name) }
        }
        model.addUserRule(path: userRule.path, keepNames: names)
    }
}

// MARK: - Panel parts

/// A raised settings group: a small title over rows on `paperRaised`, one radius step up
/// from the page. Settings is the app's only raised surface; every other page stays flat.
private struct SettingsPanel<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(Typography.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.inkSecondary)
                .padding(.horizontal, Spacing.s3)
                .padding(.top, Spacing.s2)
                .padding(.bottom, Spacing.s1)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, Spacing.s2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.paperRaised))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.hairline))
    }
}

/// The row grid every panel uses: one control column on the right, one row height. Nothing
/// in the page sets its own width or height; if a control needs a size, it fills this column.
private enum SettingsGrid {
    static let control: CGFloat = 200
    static let row: CGFloat = 34
}

/// One setting: label and optional detail on the left, the control in the shared column on
/// the right. Center alignment, because a 24 point field has no text baseline to match.
private struct SettingsRow<Control: View>: View {
    let label: String
    var detail: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(Typography.body)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let detail {
                    Text(detail)
                        .font(Typography.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            Spacer(minLength: Spacing.s3)
            control
                .frame(width: SettingsGrid.control, alignment: .trailing)
        }
        .frame(minHeight: SettingsGrid.row)
        .padding(.horizontal, Spacing.s3)
    }
}

/// The row used for a panel's own action, aligned to the same control column as a setting.
private struct SettingsActionRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: Spacing.s2) {
            Spacer(minLength: 0)
            content
                .frame(width: SettingsGrid.control, alignment: .trailing)
        }
        .frame(minHeight: SettingsGrid.row)
        .padding(.horizontal, Spacing.s3)
    }
}

private struct SettingsNote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Typography.caption)
            .foregroundStyle(Theme.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.s3)
            .padding(.top, Spacing.s1)
            .padding(.bottom, Spacing.s1)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Hairline()
            .padding(.horizontal, Spacing.s3)
    }
}
