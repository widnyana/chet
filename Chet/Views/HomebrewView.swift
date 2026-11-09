import AppKit
import ChetCore
import SwiftUI

struct HomebrewView: View {
    @Environment(HomebrewModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            PageHeader(
                title: "Homebrew",
                subtitle: subtitle,
                metric: model.packages.isEmpty
                    ? nil : model.totalBytes.formatted(.byteCount(style: .file)),
                metricLabel: "on disk"
            )
            .accessibilityIdentifier("homebrew.header")
            .padding(.horizontal, Metrics.widePageMargin)
            .padding(.top, Spacing.s6)
            .padding(.bottom, Spacing.s3)

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.paper)
        .onAppear { model.load() }
        .sheet(isPresented: $model.showInstaller) {
            HomebrewInstallerSheet()
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
            "Uninstall \(model.markedPackages.count) \(model.markedPackages.count == 1 ? "package" : "packages")?",
            isPresented: $model.showUninstallConfirm, titleVisibility: .visible
        ) {
            Button("Uninstall", role: .destructive) { model.uninstall(zap: false) }
            if model.markedPackages.contains(where: { $0.kind == .cask }) {
                Button("Uninstall and delete data", role: .destructive) { model.uninstall(zap: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                DryRun.enabled
                    ? "Preview only. Nothing will be removed."
                    : (model.markedPackages.contains(where: { $0.kind == .cask })
                        ? "This removes the packages. Removing data also deletes their settings and saved files."
                        : "This removes the packages. Homebrew can install them again."))
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
                systemImage: "shippingbox",
                actionTitle: "Open brew.sh",
                action: { NSWorkspace.shared.open(URL(string: "https://brew.sh")!) })
        } else if model.isLoading && model.packages.isEmpty {
            LoadingStateView(message: "Reading Homebrew packages")
        } else if let error = model.loadError, model.packages.isEmpty {
            EmptyStateView(
                title: "The Homebrew list could not be read.",
                message: "Run brew list in Terminal, then reload.",
                systemImage: "shippingbox",
                actionTitle: "Reload",
                action: { model.load() }
            )
            .help(error)
        } else if model.packages.isEmpty {
            EmptyStateView(
                title: "No Homebrew packages",
                message: "Install one with brew, then reload.",
                systemImage: "shippingbox",
                actionTitle: "Reload",
                action: { model.load() })
        } else {
            actionsRow
            list
            if !model.marked.isEmpty {
                CommandBar(
                    metric: model.markedBytes.formatted(.byteCount(style: .file)),
                    detail: "\(model.marked.count) selected",
                    actionTitle: "Uninstall",
                    actionSystemImage: "shippingbox",
                    isDestructive: true,
                    isWorking: model.isWorking,
                    secondaryTitle: "Deselect",
                    secondaryAction: { model.clearMarks() },
                    help: "Review and uninstall the selected packages",
                    accessibilityLabel: "Uninstall selected",
                    action: { model.showUninstallConfirm = true })
            }
        }
    }

    private var upgradeTitle: String {
        let count = model.markedOutdated.count
        return "Upgrade \(count) \(count == 1 ? "package" : "packages")"
    }

    private var actionsRow: some View {
        HStack {
            Spacer()
            SecondaryActionButton(
                title: "Update catalog",
                isEnabled: model.canAct,
                help: "Refresh Homebrew's catalog with brew update.",
                action: { model.update() })
            SecondaryActionButton(
                title: upgradeTitle,
                isEnabled: model.canUpgrade,
                help: model.canUpgrade
                    ? "Upgrade the selected packages that have an update."
                    : "Mark a package with an update first.",
                action: { model.upgrade() })
            SecondaryActionButton(
                title: "Install packages…",
                isEnabled: model.canAct,
                help: "Search for a formula or cask to install.",
                action: { model.openInstaller() })
            QuietActionButton(
                title: "Remove old versions",
                isEnabled: model.canAct,
                help: "Remove old versions and the download cache.",
                action: { model.cleanup() })
            if model.isWorking || model.isUpdating { ProgressView().controlSize(.mini) }
        }
        .padding(.horizontal, Metrics.widePageMargin)
        .padding(.bottom, Spacing.s2)
    }

    private var list: some View {
        ColumnTable(items: model.sortedPackages) {
            header
        } row: { package in
            HomebrewRow(package: package)
        }
    }

    private var header: some View {
        HStack(spacing: HomebrewColumns.spacing) {
            Color.clear.frame(width: HomebrewColumns.mark)
            sortButton("Name", .name).frame(maxWidth: .infinity, alignment: .leading)
            sortButton("Kind", .kind).frame(width: HomebrewColumns.kind, alignment: .leading)
            sortButton("Version", .version)
                .frame(width: HomebrewColumns.version, alignment: .leading)
            sortButton("Size", .size).frame(width: HomebrewColumns.size, alignment: .trailing)
            sortButton("Status", .status)
                .frame(width: HomebrewColumns.status, alignment: .leading)
        }
        .padding(.horizontal, Metrics.widePageMargin)
        .padding(.vertical, Spacing.s2)
    }

    private func sortButton(_ title: String, _ column: BrewSort) -> some View {
        Button {
            model.setSort(column)
        } label: {
            HStack(spacing: 2) {
                Text(title).font(Typography.caption).fontWeight(.semibold)
                Image(systemName: model.ascending ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .opacity(model.sort == column ? 1 : 0)
            }
            .foregroundStyle(model.sort == column ? Theme.ink : Theme.inkSecondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Sort by \(title)")
        .accessibilityLabel(title)
        .accessibilityIdentifier("homebrew.sort.\(column.rawValue)")
    }
}

/// Stable column metrics shared by the Homebrew header and its rows.
private enum HomebrewColumns {
    static let mark: CGFloat = 20
    static let kind: CGFloat = 64
    static let version: CGFloat = 110
    static let size: CGFloat = 80
    static let status: CGFloat = 140
    static let spacing: CGFloat = Spacing.s3
}

private struct HomebrewRow: View {
    @Environment(HomebrewModel.self) private var model
    let package: BrewPackage

    var body: some View {
        HStack(spacing: HomebrewColumns.spacing) {
            Toggle(
                "",
                isOn: Binding(
                    get: { model.marked.contains(package.id) },
                    set: { model.setMark(package, on: $0) })
            )
            .labelsHidden()
            .toggleStyle(.checkbox)
            .frame(width: HomebrewColumns.mark)
            .accessibilityLabel("Select \(package.title) to uninstall")
            .accessibilityIdentifier("homebrew.select.\(package.id)")
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
                .frame(width: HomebrewColumns.kind, alignment: .leading)
            Text(package.version)
                .font(Typography.caption).monospacedDigit().foregroundStyle(Theme.inkSecondary)
                .lineLimit(1).frame(width: HomebrewColumns.version, alignment: .leading)
            Text(package.size.formatted(.byteCount(style: .file)))
                .font(Typography.caption).monospacedDigit().foregroundStyle(Theme.ink)
                .frame(width: HomebrewColumns.size, alignment: .trailing)
            statusLabel.frame(width: HomebrewColumns.status, alignment: .leading)
        }
        .padding(.horizontal, Metrics.widePageMargin)
        .padding(.vertical, Spacing.s2)
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
