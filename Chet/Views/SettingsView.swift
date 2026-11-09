import AppKit
import ChetCore
import SwiftUI

/// Settings page (Cmd+,). Three panes, the macOS preference arrangement: a toolbar pane
/// switcher, then grouped panels with the label on the left and its control on the right.
/// The words are for someone who has never opened a terminal. Every value applies to the
/// next scan. The parts live in `SettingsComponents.swift`; this file only composes them.
struct SettingsView: View {
    @Environment(ScanModel.self) private var model
    @State private var pane: SettingsPane = .whatToFind

    private let optionalSteps: [ScanStep] = [.largeFiles, .duplicates, .leftovers, .photos, .videos, .snapshots]

    var body: some View {
        VStack(spacing: 0) {
            if DryRun.enabled {
                StatusStrip(
                    text: "Preview only. Nothing will be removed.",
                    systemImage: "eye.slash",
                    tone: .amber)
            }
            SettingsPaneSwitcher(selection: $pane)
            Hairline()
            Group {
                switch pane {
                case .whatToFind: scanPane
                case .limits: sizesPane
                case .folders: foldersPane
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.paper)
        .tint(Theme.accent)
        .frame(width: 560, height: 560)
        .background(SettingsWindowChrome())
    }

    // MARK: - Scan

    private var scanPane: some View {
        SettingsPaneView {
            SettingsPanel(title: "What to look for") {
                SettingsNote("Chet always checks the usual places and measures your folders.")
                ForEach(optionalSteps, id: \.rawValue) { step in
                    let copy = optionalCopy(step)
                    SettingsDivider()
                    SettingsToggleRow(
                        label: copy.title,
                        detail: copy.detail,
                        isOn: Binding(
                            get: { model.isStepEnabled(step) },
                            set: { model.setStep(step, enabled: $0) }))
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
        let title = ScanStepCopy.title(step)
        switch step {
        case .largeFiles: return (title, "Files above the size limit, or older than the age limit.")
        case .duplicates: return (title, "Files with identical contents.")
        case .leftovers: return (title, "Data left after an app was deleted.")
        case .photos: return (title, "Copies and near-copies of the same photo.")
        case .videos: return (title, "Re-encoded copies of the same video.")
        case .snapshots: return (title, "Local copies Time Machine keeps on this disk.")
        case .rules, .index: return (title, "")
        }
    }

    // MARK: - Sizes

    private var sizesPane: some View {
        SettingsPaneView {
            SettingsPanel(title: "Duplicate files") {
                SettingsNote("Copies smaller than this are left alone.")
                SettingsDivider()
                SettingsSliderRow(
                    label: "Smallest file to compare", readout: "\(model.duplicateMinSizeMB) MB",
                    value: Binding(
                        get: { Double(model.duplicateMinSizeMB) },
                        set: { model.duplicateMinSizeMB = Int($0) }),
                    range: 1...100, step: 1)
                SettingsDivider()
                SettingsToggleRow(
                    label: "Look inside temporary app files",
                    detail: "Apps rebuild them when they need them.",
                    isOn: Binding(
                        get: { model.includeTempInDuplicates },
                        set: { model.includeTempInDuplicates = $0 }))
            }
            SettingsPanel(title: "Large files") {
                SettingsNote("Files this large are listed even if you used them today.")
                SettingsDivider()
                SettingsSliderRow(
                    label: "Large file size", readout: "\(model.largeFileMinSizeMB) MB",
                    value: Binding(
                        get: { Double(model.largeFileMinSizeMB) },
                        set: { model.largeFileMinSizeMB = Int($0) }),
                    range: 50...2000, step: 50)
            }
            SettingsPanel(title: "Old files") {
                SettingsNote("Large files you have not used for this long are listed.")
                SettingsDivider()
                SettingsSliderRow(
                    label: "Unchanged for", readout: "\(model.largeFileOldAgeDays) days",
                    value: Binding(
                        get: { Double(model.largeFileOldAgeDays) },
                        set: { model.largeFileOldAgeDays = Int($0) }),
                    range: 30...730, step: 30)
            }
        }
    }

    // MARK: - Folders

    private var foldersPane: some View {
        SettingsPaneView {
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
                SettingsToggleRow(
                    label: "Also look on other disks",
                    detail: "For files kept on an external disk.",
                    isOn: Binding(
                        get: { model.scanOutsideHome },
                        set: { model.scanOutsideHome = $0 }))
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
        panel.message = "Choose folders. Chet lists what each one contains."
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
