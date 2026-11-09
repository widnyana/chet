import AppKit
import MackitCore
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
                    text: "Preview only. Nothing is deleted.",
                    systemImage: "eye.slash",
                    tone: .amber)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Metrics.pageMargin)
                    .padding(.vertical, Spacing.s2)
                    .background(Theme.paperRaised)
            }
            TabView {
                scanPane.tabItem { Label("Scan", systemImage: "magnifyingglass") }
                sizesPane.tabItem { Label("Sizes", systemImage: "ruler") }
                foldersPane.tabItem { Label("Folders", systemImage: "folder") }
            }
        }
        .background(Theme.paper)
        .tint(Theme.accent)
        .frame(width: 520, height: 500)
        .background(SettingsWindowChrome())
    }

    private func pane<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                content()
            }
            .padding(Spacing.s4)
        }
    }

    // MARK: - Scan

    private var scanPane: some View {
        pane {
            SettingsPanel(title: "What Mackit looks for") {
                SettingsNote("Two checks always run: Mackit's own folder list, and measuring your folders.")
                ForEach(optionalSteps, id: \.rawValue) { step in
                    SettingsDivider()
                    SettingsRow(label: step.title) {
                        Toggle("", isOn: Binding(
                            get: { model.isStepEnabled(step) },
                            set: { model.setStep(step, enabled: $0) }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .accessibilityLabel(step.title)
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

    // MARK: - Sizes
    private var sizesPane: some View {
        pane {
            SettingsPanel(title: "Copies") {
                SettingsNote("Copies below this size are left alone.")
                SettingsDivider()
                sliderRow(
                    title: "Smallest copy", value: "\(model.duplicateMinSizeMB) MB",
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
                SettingsNote("A file this big is listed even if you used it today.")
                SettingsDivider()
                sliderRow(
                    title: "Big file size", value: "\(model.largeFileMinSizeMB) MB",
                    binding: Binding(
                        get: { Double(model.largeFileMinSizeMB) },
                        set: { model.largeFileMinSizeMB = Int($0) }),
                    range: 50...2000, step: 50)
            }
            SettingsPanel(title: "Old files") {
                SettingsNote("Files you have not touched for this long count as old.")
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
            SettingsPanel(title: "Folders to skip") {
                SettingsNote("Mackit never looks inside these, and never deletes here.")
                if model.excludedPaths.isEmpty {
                    SettingsNote("No folders are skipped.")
                } else {
                    ForEach(model.excludedPaths, id: \.self) { path in
                        SettingsDivider()
                        SettingsRow(label: path) {
                            Button("Remove") { model.removeExcludedPath(path) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .accessibilityLabel("Stop skipping \(path)")
                        }
                    }
                }
                SettingsDivider()
                SettingsActionRow {
                    Button("Skip a Folder…") { chooseExcludedFolders() }
                        .controlSize(.small)
                        .accessibilityLabel("Choose a folder to skip")
                }
            }
            SettingsPanel(title: "Folders you add") {
                SettingsNote("Everything inside is listed, you approve it, then it goes to the Trash.")
                if model.userRules.isEmpty {
                    SettingsNote("No folders added yet.")
                } else {
                    ForEach(model.userRules) { userRule in
                        SettingsDivider()
                        SettingsRow(label: userRule.path) {
                            Button("Remove") { model.removeUserRule(userRule.id) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .accessibilityLabel("Remove folder \(userRule.path)")
                        }
                    }
                }
                SettingsDivider()
                SettingsActionRow {
                    Button("Add a Folder…") { chooseRuleFolders() }
                        .controlSize(.small)
                        .accessibilityLabel("Add a folder to check")
                }
            }
            SettingsPanel(title: "Other drives") {
                SettingsRow(
                    label: "Also look on other drives",
                    detail: "For machines or projects kept on another disk."
                ) {
                    Toggle("", isOn: Binding(
                        get: { model.scanOutsideHome },
                        set: { model.scanOutsideHome = $0 }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .accessibilityLabel("Also look on other drives")
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
        panel.message = "Choose folders Mackit should never look inside."
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
        panel.message = "Choose folders Mackit should check for things you can remove."
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            model.addUserRule(path: url.path)
        }
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
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.paperRaised))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
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
