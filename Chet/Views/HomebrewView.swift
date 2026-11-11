import AppKit
import ChetCore
import SwiftUI

struct HomebrewView: View {
    private enum UpgradeRequest {
        case marked
        case package(BrewPackage)
    }

    @Environment(HomebrewModel.self) private var model
    @State private var query = ""
    @State private var pendingUpgrade: UpgradeRequest?
    @State private var showingCleanup = false

    var body: some View {
        @Bindable var model = model
        PageScreen(
            scrolls: false,
            header: {
                PageHeader(
                    title: "Homebrew",
                    subtitle: subtitle
                )
                .accessibilityIdentifier("homebrew.header")
            },
            content: { content },
            bar: { commandBar }
        )
        .onAppear { model.load() }
        .onAppear {
            VerboseLog.event(.debug, .ui, .uiViewAppeared, .code(.view, .viewHomebrew))
        }
        .onChange(of: model.showInstaller) { _, showing in
            if showing {
                VerboseLog.event(.debug, .ui, .uiSheetPresented, .code(.sheet, .sheetInstaller))
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Search packages")
        .sheet(isPresented: $model.showInstaller) {
            HomebrewInstallerSheet()
        }
        .sheet(isPresented: $model.showUninstallConfirm) {
            HomebrewUninstallSheet()
        }
        .sheet(isPresented: $showingCleanup) {
            HomebrewCleanupSheet()
        }
        .alert(
            "Homebrew",
            isPresented: Binding(
                get: { model.actionResult != nil },
                set: { if !$0 { model.actionResult = nil } })
        ) {
            Button("OK", role: .cancel) { model.actionResult = nil }
        } message: {
            Text(model.actionResult ?? "")
        }
        .confirmationDialog(
            pendingUpgradeTitle + "?",
            isPresented: Binding(
                get: { pendingUpgrade != nil },
                set: { if !$0 { pendingUpgrade = nil } }),
            titleVisibility: .visible
        ) {
            Button("Upgrade") {
                switch pendingUpgrade {
                case .marked: model.upgrade()
                case .package(let package): model.upgrade(package)
                case nil: break
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                DryRun.enabled
                    ? PreviewCopy.removals
                        + " Homebrew would replace \(pendingUpgradeTarget) with the latest versions."
                    : "Homebrew replaces \(pendingUpgradeTarget) with the latest versions.")
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.openInstaller()
                } label: {
                    Label("Install packages…", systemImage: "plus")
                }
                .help("Search for a formula or cask to install")
                .accessibilityIdentifier("homebrew.install")

                Button {
                    model.load()
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .disabled(model.isLoading)
                .help("Read the Homebrew list again")

                Menu {
                    Button("Update catalog", systemImage: "arrow.triangle.2.circlepath") {
                        model.update()
                    }
                    .disabled(!model.canAct)
                    Button(upgradeTitle, systemImage: "arrow.up.circle") {
                        pendingUpgrade = .marked
                    }
                    .disabled(!model.canUpgrade)
                    Button("Remove old versions…", systemImage: "trash") {
                        showingCleanup = true
                    }
                    .disabled(!model.canAct)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .help("Update, upgrade, or clean up")
            }
        }
    }

    private var subtitle: String {
        guard model.isAvailable else { return "Install Homebrew to manage packages here." }
        let count = model.packages.count
        return "\(count) \(count == 1 ? "package" : "packages"), \(model.marked.count) marked"
    }

    @ViewBuilder private var content: some View {
        if !model.isAvailable {
            EmptyStateView(
                title: "Homebrew is not installed",
                message: "Install it from brew.sh, then reload.",
                actionTitle: "Open brew.sh",
                action: { NSWorkspace.shared.open(URL(string: "https://brew.sh")!) }
            )
            .pageHorizontalPadding()
        } else if model.isLoading && model.packages.isEmpty {
            LoadingStateView(message: "Reading Homebrew packages")
                .pageHorizontalPadding()
        } else if let error = model.loadError, model.packages.isEmpty {
            ErrorStateView(
                title: "The Homebrew list could not be read.",
                message: "Run brew list in Terminal, then reload.",
                actionTitle: "Reload",
                action: { model.load() }
            )
            .help(error)
            .pageHorizontalPadding()
        } else if model.packages.isEmpty {
            EmptyStateView(
                title: "No Homebrew packages",
                message: "Install one with brew, then reload.",
                actionTitle: "Reload",
                action: { model.load() }
            )
            .pageHorizontalPadding()
        } else if visiblePackages.isEmpty {
            EmptyStateView(
                title: "No package matches \"\(query)\"",
                message: "Clear the search to see all packages.",
                actionTitle: "Clear search",
                action: { query = "" }
            )
            .pageHorizontalPadding()
        } else {
            if let error = model.loadError {
                StatusLabel(
                    text: "The Homebrew list could not be read.",
                    systemImage: "exclamationmark.triangle",
                    tone: .amber,
                    help: error
                )
                .pageHorizontalPadding()
                .padding(.bottom, Spacing.s2)
            }
            list
        }
    }

    private var visiblePackages: [BrewPackage] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return model.sortedPackages }
        return model.sortedPackages.filter {
            $0.name.localizedCaseInsensitiveContains(text)
                || $0.title.localizedCaseInsensitiveContains(text)
                || $0.desc.localizedCaseInsensitiveContains(text)
        }
    }

    private var commandBar: some View {
        CommandBar(
            metric: model.markedBytes.formatted(.byteCount(style: .file)),
            detail: model.marked.isEmpty
                ? "No packages selected"
                : "\(model.marked.count) \(model.marked.count == 1 ? "package selected" : "packages selected")",
            actionTitle: "Uninstall",
            actionSystemImage: "shippingbox",
            isEnabled: !model.marked.isEmpty && model.canAct,
            isWorking: model.isWorking,
            secondaryTitle: model.marked.isEmpty ? nil : "Deselect",
            secondaryAction: model.marked.isEmpty ? nil : { model.clearMarks() },
            help: "Review and uninstall the selected packages",
            accessibilityLabel: "Uninstall \(model.marked.count) selected packages",
            disabledReason: model.marked.isEmpty ? "Select a package to uninstall." : nil,
            action: { model.showUninstallConfirm = true })
    }

    private var upgradeTitle: String {
        upgradeLabel(model.markedOutdated.count)
    }

    private func upgradeLabel(_ count: Int) -> String {
        "Upgrade \(count) \(count == 1 ? "package" : "packages")"
    }

    private var pendingUpgradeTitle: String {
        switch pendingUpgrade {
        case .marked: return upgradeLabel(model.markedOutdated.count)
        case .package: return upgradeLabel(1)
        case nil: return upgradeLabel(0)
        }
    }

    private var pendingUpgradeTarget: String {
        switch pendingUpgrade {
        case .marked: return "the selected packages"
        case .package: return "the package"
        case nil: return "nothing"
        }
    }

    private var list: some View {
        ColumnTable(items: visiblePackages) {
            header
        } row: { package in
            HomebrewRow(package: package) { pendingUpgrade = .package(package) }
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: ColumnRegistry.spacing) {
                Color.clear.frame(width: ColumnRegistry.spec(.mark).width)
                Color.clear.frame(width: ColumnRegistry.spec(.icon).width)
                sortButton("Name", .name).frame(maxWidth: .infinity, alignment: .leading)
                sortButton("Kind", .kind).frame(width: ColumnRegistry.spec(.kind).width, alignment: .leading)
                sortButton("Version", .version)
                    .frame(width: ColumnRegistry.spec(.version).width, alignment: .leading)
                sortButton("Size", .size).frame(width: ColumnRegistry.spec(.size).width, alignment: .trailing)
                sortButton("Status", .status)
                    .frame(width: ColumnRegistry.spec(.status).width, alignment: .leading)
            }
            .pageHorizontalPadding()
            .padding(.vertical, Spacing.s2)
            Hairline()
        }
    }

    private func sortButton(_ title: String, _ column: BrewSort) -> some View {
        SortColumnButton(
            title: title,
            isActive: model.sort == column,
            ascending: model.ascending,
            identifier: "homebrew.sort.\(column.rawValue)"
        ) {
            model.setSort(column)
        }
    }
}

private struct HomebrewRow: View {
    @Environment(HomebrewModel.self) private var model
    let package: BrewPackage
    let onUpgrade: () -> Void

    private var isUpgradeEnabled: Bool { model.canAct && package.outdated }

    var body: some View {
        TableRow(
            isHighlighted: model.marked.contains(package.id),
            content: {
                HStack(spacing: ColumnRegistry.spacing) {
                    RowCheckbox(
                        isOn: Binding(
                            get: { model.marked.contains(package.id) },
                            set: { model.setMark(package, on: $0) }),
                        label: "Select \(package.title) to uninstall",
                        width: ColumnRegistry.spec(.mark).width,
                        identifier: "homebrew.select.\(package.id)")
                    Image(systemName: package.kind == .cask ? "shippingbox.fill" : "shippingbox")
                        .font(Typography.iconRow)
                        .foregroundStyle(Theme.inkSecondary)
                        .frame(width: ColumnRegistry.spec(.icon).width)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(package.title).font(Typography.row).foregroundStyle(Theme.ink).lineLimit(1)
                        if !package.desc.isEmpty {
                            Text(package.desc)
                                .font(Typography.caption).foregroundStyle(Theme.inkSecondary).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(package.kindLabel)
                        .font(Typography.caption).foregroundStyle(Theme.inkSecondary)
                        .frame(width: ColumnRegistry.spec(.kind).width, alignment: .leading)
                    Text(package.version)
                        .font(Typography.caption).monospacedDigit().foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1).frame(width: ColumnRegistry.spec(.version).width, alignment: .leading)
                    SizeColumn(bytes: package.size, width: ColumnRegistry.spec(.size).width)
                    statusLabel.frame(width: ColumnRegistry.spec(.status).width, alignment: .leading)
                    if package.outdated {
                        QuietActionButton(
                            title: "Upgrade",
                            isEnabled: isUpgradeEnabled,
                            help: "Upgrade \(package.title) to \(package.latest).",
                            accessibilityLabel: "Upgrade \(package.title)",
                            action: onUpgrade
                        )
                        .accessibilityIdentifier("homebrew.upgrade.\(package.id)")
                    }
                }
            }
        )
        .contextMenu {
            if package.outdated {
                Button("Upgrade") { onUpgrade() }
                    .disabled(!isUpgradeEnabled)
            }
        }
    }

    @ViewBuilder private var statusLabel: some View {
        if package.outdated {
            StatusLabel(
                text: "Outdated", systemImage: "arrow.up.circle", tone: .amber,
                help: "Latest is \(package.latest).")
        } else if package.isUnusedDependency {
            StatusLabel(
                text: "Unused", systemImage: "questionmark.circle", tone: .neutral,
                help: "Installed as a dependency, now used by nothing.")
        } else if package.pinned {
            StatusLabel(text: "Pinned", systemImage: "pin", tone: .neutral)
        } else {
            Color.clear.frame(height: 1)
        }
    }
}
