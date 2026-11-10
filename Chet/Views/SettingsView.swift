import AppKit
import ChetCore
import SwiftUI

/// Settings page (Cmd+,). Four panes, the macOS preference arrangement: a toolbar pane
/// switcher, then grouped panels with the label on the left and its control on the right.
/// The words are for someone who has never opened a terminal. Every value applies to the
/// next scan. The parts live in `SettingsComponents.swift`; this file only composes them.
struct SettingsView: View {
    @Environment(ScanModel.self) private var model
    @Environment(TweaksModel.self) private var tweaks
    @State private var pane: SettingsPane = .whatToFind
    @State private var confirmingReset = false
    @State private var resetting = false
    @State private var helperState = HelperService.state
    @State private var helperBusy = false
    @State private var helperError: String?

    private let optionalSteps: [ScanStep] = [.largeFiles, .duplicates, .leftovers, .photos, .videos, .snapshots]

    var body: some View {
        VStack(spacing: 0) {
            if DryRun.enabled {
                PreviewNotice(text: "Preview only. Nothing will be removed.")
                    .padding(.horizontal, Metrics.pageMargin)
                    .padding(.top, Spacing.s4)
            }
            TabView(selection: $pane) {
                scanPane
                    .tabItem {
                        Label(SettingsPane.whatToFind.title, systemImage: SettingsPane.whatToFind.systemImage)
                    }
                    .tag(SettingsPane.whatToFind)
                sizesPane
                    .tabItem {
                        Label(SettingsPane.limits.title, systemImage: SettingsPane.limits.systemImage)
                    }
                    .tag(SettingsPane.limits)
                foldersPane
                    .tabItem {
                        Label(SettingsPane.folders.title, systemImage: SettingsPane.folders.systemImage)
                    }
                    .tag(SettingsPane.folders)
                tweaksPane
                    .tabItem {
                        Label(SettingsPane.tweaks.title, systemImage: SettingsPane.tweaks.systemImage)
                    }
                    .tag(SettingsPane.tweaks)
            }
        }
        .frame(width: 560, height: 560)
        .confirmationDialog(
            "Reset every tweak?", isPresented: $confirmingReset, titleVisibility: .visible
        ) {
            Button("Reset All", role: .destructive) {
                Task {
                    resetting = true
                    await tweaks.resetEverything()
                    resetting = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every tweak goes back to the macOS default. Files, apps, and caches are not touched.")
        }
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
                    Picker(
                        "Threads",
                        selection: Binding(
                            get: { model.scanThreads },
                            set: { model.scanThreads = $0 })
                    ) {
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
            SettingsPanel(title: "Administrator") {
                SettingsNote(helperStatusLine)
                if let helperError {
                    SettingsNote(helperError)
                }
                SettingsDivider()
                SettingsRow(label: "Administrator cleanup") {
                    SecondaryActionButton(
                        title: helperOn ? "Turn Off" : "Turn On…",
                        isEnabled: !DryRun.enabled && !helperBusy && helperState != .unsupported,
                        help: helperState == .unsupported
                            ? "Requires a Developer ID signed build"
                            : "Turn on cleanup for system caches, logs, and app remnants",
                        accessibilityLabel: "Administrator cleanup",
                        action: { helperOn ? turnHelperOff() : turnHelperOn() }
                    )
                    .accessibilityIdentifier("settings.helper.toggle")
                }
                if helperState == .needsApproval {
                    SettingsDivider()
                    SettingsActionRow {
                        SecondaryActionButton(
                            title: "Open System Settings",
                            isEnabled: !DryRun.enabled,
                            help: "Approve Chet in Login Items and Extensions",
                            action: openApprovalSettings
                        )
                        .accessibilityIdentifier("settings.helper.openSettings")
                    }
                }
                SettingsDivider()
                SettingsSliderRow(
                    label: "Approval lifetime", readout: "\(model.helperLifetimeMinutes) minutes",
                    value: Binding(
                        get: { Double(model.helperLifetimeMinutes) },
                        set: { model.helperLifetimeMinutes = Int($0) }),
                    range: 1...60, step: 1,
                    isEnabled: !DryRun.enabled && helperState != .unsupported
                )
                .accessibilityIdentifier("settings.helper.lifetime")
            }
        }
        .onAppear { refreshHelperStatus() }
    }

    // MARK: - Administrator helper

    private var helperOn: Bool {
        helperState == .enabled || helperState == .needsApproval
    }

    private var helperStatusLine: String {
        switch helperState {
        case .enabled:
            return
                "Administrator cleanup is on. Each approval lasts \(model.helperLifetimeMinutes) minutes."
        case .needsApproval:
            return "Approve Chet in System Settings to turn it on."
        case .missing:
            return "The helper is missing. Reinstall Chet in Applications."
        case .unsupported:
            return
                "Administrator cleanup needs a Developer ID signed copy. This build is ad-hoc signed, so macOS refuses the helper."
        case .off:
            return "Administrator cleanup is off. Chet never asks for an administrator."
        }
    }

    private func refreshHelperStatus() {
        helperState = HelperService.state
    }

    private func turnHelperOn() {
        guard !DryRun.enabled else { return }
        helperError = nil
        do {
            try HelperService.register()
        } catch {
            helperError = error.localizedDescription
        }
        refreshHelperStatus()
    }

    private func turnHelperOff() {
        guard !DryRun.enabled else { return }
        helperError = nil
        helperBusy = true
        Task {
            do {
                try await HelperService.unregister()
            } catch {
                helperError = error.localizedDescription
            }
            helperBusy = false
            refreshHelperStatus()
        }
    }

    private func openApprovalSettings() {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
        else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Tweaks

    private var tweaksPane: some View {
        SettingsPaneView(note: "Changes apply as soon as each value is written.") {
            SettingsPanel(title: "Changes Chet made") {
                SettingsNote(TweakCopy.verificationNote)
                SettingsDivider()
                SettingsRow(label: "Changed from the macOS default", detail: changedDetail) {
                    Text("\(tweaks.customizedCount)")
                        .font(Typography.row)
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                }
                SettingsDivider()
                SettingsRow(label: "Change record", detail: recordPath) {
                    SecondaryActionButton(
                        title: "Show",
                        isEnabled: FileManager.default.fileExists(atPath: tweaks.historyURL.path),
                        help: "Show the tweak record in Finder"
                    ) {
                        revealRecord()
                    }
                }
            }
            SettingsPanel(title: "Reset") {
                SettingsNote(
                    "Reset puts every changed tweak back to the macOS default. It does not touch files, caches, or apps."
                )
                if tweaks.isGated {
                    SettingsNote("Preview only. No tweak is changed.")
                }
                if let message = tweaks.errorMessage {
                    SettingsNote(message)
                }
                SettingsDivider()
                SettingsActionRow {
                    SecondaryActionButton(
                        title: resetting ? "Resetting…" : "Reset All…",
                        isEnabled: resetEnabled,
                        help: "Put every changed tweak back to its macOS default"
                    ) {
                        confirmingReset = true
                    }
                }
            }
        }
        .task { await tweaks.ensureLoaded() }
    }

    private var changedDetail: String {
        let count = tweaks.customizedCount
        return count == 1 ? "1 tweak differs." : "\(count) tweaks differ."
    }

    private var resetEnabled: Bool {
        tweaks.customizedCount > 0 && !tweaks.isGated && !resetting
    }

    private var recordPath: String {
        let path = tweaks.historyURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private func revealRecord() {
        let url = tweaks.historyURL
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
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
