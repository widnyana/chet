import AppKit
import ChetCore
import SwiftUI

/// The categories and folders one scan reads. Everything is on until the user turns something
/// off, so an empty selection scans the whole Mac the way Chet always has.
struct ScanScopeSheet: View {
    @Environment(ScanModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private var entries: [CategoryCopy.ScopeEntry] { CategoryCopy.scopeEntries }

    var body: some View {
        SheetFrame(width: Metrics.sheetWidth, height: 620) {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                header
                ScrollView {
                    VStack(spacing: Spacing.s4) {
                        panel(.safe)
                        panel(.review)
                        panel(.informational)
                        folderPanel
                        rememberPanel
                    }
                    .padding(.bottom, Spacing.s2)
                }
                footer
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            Text("Scan a part of this Mac")
                .font(Typography.title)
                .accessibilityIdentifier("scan.scope")
            Text("Pick the categories and folders one scan reads. Everything else is left alone.")
                .font(Typography.body)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private func panel(_ section: CategorySection) -> some View {
        let rows = entries.filter { $0.section == section }
        if !rows.isEmpty {
            SettingsPanel(title: Self.title(section)) {
                ForEach(rows) { entry in
                    SettingsDivider()
                    SettingsToggleRow(
                        label: entry.title, detail: entry.explanation,
                        isOn: binding(for: entry.id),
                        identifier: "scan.scope.category.\(entry.id)")
                }
            }
        }
    }

    private var folderPanel: some View {
        SettingsPanel(title: "Folders") {
            SettingsNote(
                "No folder means your home folders, without Library. A folder outside your home needs Other disks in Settings."
            )
            ForEach(Array(model.scope.roots.enumerated()), id: \.element) { index, path in
                SettingsDivider()
                SettingsRow(label: (path as NSString).abbreviatingWithTildeInPath) {
                    IconActionButton(
                        systemImage: "xmark", label: "Stop scanning \(path)",
                        help: "Remove this folder from the scan"
                    ) {
                        model.scope.roots.removeAll { $0 == path }
                    }
                    .accessibilityIdentifier("scan.scope.remove.\(index)")
                }
            }
            SettingsDivider()
            SettingsRow(label: "Add a folder") {
                SecondaryActionButton(
                    title: "Choose…", help: "Read only inside this folder in the next scan"
                ) {
                    addFolder()
                }
                .accessibilityIdentifier("scan.scope.add")
            }
        }
    }

    private var rememberPanel: some View {
        SettingsPanel(title: "Next launch") {
            SettingsToggleRow(
                label: "Remember this scope",
                detail: "Otherwise the next launch scans everything again.",
                isOn: Binding(
                    get: { model.remembersScope }, set: { model.remembersScope = $0 }),
                identifier: "scan.scope.remember")
        }
    }

    private var footer: some View {
        HStack(spacing: Spacing.s3) {
            Text(summary)
                .font(Typography.caption)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Spacing.s3)
            SecondaryActionButton(title: "Cancel") { dismiss() }
                .accessibilityIdentifier("scan.scope.cancel")
            PrimaryActionButton(title: "Scan") {
                model.scan()
                dismiss()
            }
            .accessibilityIdentifier("scan.scope.apply")
        }
    }

    private var summary: String {
        let scope = model.scope.normalized()
        guard scope.isPartial else { return "Everything." }
        return "\(ScanModel.summary(for: scope)). Nothing else is read."
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { model.scope.categories.isEmpty || model.scope.categories.contains(id) },
            set: { isOn in select(id, on: isOn) })
    }

    private func select(_ id: String, on: Bool) {
        let everyCategory = Set(ScanScope.knownCategories)
        var selected = model.scope.categories.isEmpty ? everyCategory : model.scope.categories
        if on {
            selected.insert(id)
        } else {
            selected.remove(id)
        }
        model.scope.categories = selected.count == everyCategory.count ? [] : selected
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Scan This Folder"
        panel.message = "The next scan reads only inside this folder."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.standardizedFileURL.path
        guard !model.scope.roots.contains(path) else { return }
        model.scope.roots.append(path)
    }

    private static func title(_ section: CategorySection) -> String {
        switch section {
        case .safe: return "Safe to remove"
        case .review: return "Check first"
        case .informational: return "Protected"
        }
    }
}
