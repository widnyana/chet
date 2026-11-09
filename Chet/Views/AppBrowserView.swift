import AppKit
import ChetCore
import SwiftUI

/// The uninstall destination: the inventory (list or grid) plus the bulk flow.
/// Opening one app pushes the review surface; marking several apps opens the
/// bulk pass. The sheets attach here so the summary survives the pop.
struct UninstallWorkspace: View {
    @Environment(AppCleanerModel.self) private var model

    var body: some View {
        NavigationStack {
            AppBrowserView()
                .navigationDestination(item: selectionBinding) { id in
                    if let app = model.apps.first(where: { $0.url == id }) {
                        AppCleanerDetailView(app: app)
                    }
                }
        }
        .onAppear { model.load() }
        .sheet(
            isPresented: Binding(
                get: { model.report != nil },
                set: { if !$0 { model.report = nil } })
        ) {
            if let report = model.report { UninstallSummaryView(report: report) }
        }
        .sheet(isPresented: bulkConfirmBinding) {
            BulkUninstallConfirmSheet()
        }
        .sheet(
            isPresented: Binding(
                get: { model.bulkReport != nil },
                set: { if !$0 { model.bulkReport = nil } })
        ) {
            if let report = model.bulkReport { BulkUninstallSummaryView(report: report) }
        }
        .onReceive(
            NSWorkspace.shared.notificationCenter.publisher(
                for: NSWorkspace.didTerminateApplicationNotification)
        ) { _ in
            model.refreshRunningState()
        }
        .onReceive(
            NSWorkspace.shared.notificationCenter.publisher(
                for: NSWorkspace.didLaunchApplicationNotification)
        ) { _ in
            model.refreshRunningState()
        }
    }

    private var selectionBinding: Binding<URL?> {
        Binding(
            get: { model.selectedAppID },
            set: { id in
                model.select(id.flatMap { id in model.apps.first { $0.url == id } })
            })
    }

    private var bulkConfirmBinding: Binding<Bool> {
        Binding(
            get: { model.showBulkConfirm && !model.markedApps.isEmpty },
            set: { model.showBulkConfirm = $0 })
    }
}

struct AppBrowserView: View {
    @Environment(AppCleanerModel.self) private var model

    private let columns = [GridItem(.adaptive(minimum: 164), spacing: Spacing.s3)]
    @State private var sort: AppSort = .name
    @State private var ascending = true

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            PageHeader(
                title: "Apps",
                subtitle: subtitle,
                metric: nil
            )
            .accessibilityIdentifier("apps.header")
            .padding(.horizontal, Metrics.widePageMargin)
            .padding(.top, Spacing.s6)
            .padding(.bottom, Spacing.s3)
            if model.isLoadingApps {
                LoadingStateView(message: "Reading your apps")
                    .padding(.horizontal, Metrics.widePageMargin)
                Spacer()
            } else if model.apps.isEmpty {
                noApps
                    .padding(.horizontal, Metrics.widePageMargin)
            } else if model.filteredApps.isEmpty {
                EmptyStateView(
                    title: "No apps match",
                    message: "No app name contains \"\(model.query)\".",
                    systemImage: "magnifyingglass",
                    actionTitle: "Clear search",
                    action: { model.query = "" }
                )
                .padding(.horizontal, Metrics.widePageMargin)
            } else {
                switch model.style {
                case .grid: grid
                case .list: list
                }
            }
        }
        .background(Theme.paper)
        .searchable(text: $model.query, placement: .toolbar, prompt: "Search apps")
        .safeAreaInset(edge: .bottom) {
            if model.isBulkRemoving || !model.markedApps.isEmpty {
                bulkBar
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("Layout", selection: $model.style) {
                    ForEach(AppBrowserStyle.allCases) { style in
                        Image(systemName: style.systemImage)
                            .help(style.title)
                            .tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("Show the inventory as a list or a grid")

                Button {
                    model.load()
                } label: {
                    Label("Reload applications", systemImage: "arrow.clockwise")
                }
                .disabled(model.isLoadingApps)
                .help("Read the applications folder again")
            }
        }
    }

    private var subtitle: String {
        model.apps.isEmpty ? "Installed apps" : "\(model.apps.count) installed"
    }

    @ViewBuilder private var noApps: some View {
        if model.hasFullDiskAccess {
            EmptyStateView(
                title: "No apps found",
                message: "Try reading the Applications folder again.",
                systemImage: "app.dashed",
                actionTitle: "Reload",
                action: { model.load() })
        } else {
            EmptyStateView(
                title: "No apps found",
                message: "Chet may not see every app without Full Disk Access.",
                systemImage: "app.dashed",
                actionTitle: "Open Settings",
                action: { NSWorkspace.shared.open(FullDiskAccess.settingsURL) })
        }
    }

    /// The filtered inventory in the user's chosen column order. Every column is sortable
    /// (repo rule); the header toggles the column and the direction.
    private var sortedApps: [InstalledApp] {
        let apps = model.filteredApps
        let ordered: [InstalledApp]
        switch sort {
        case .name:
            ordered = apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .lastUsed:
            ordered = apps.sorted { lastUsedKey($0) < lastUsedKey($1) }
        case .size:
            ordered = apps.sorted { (model.appSizes[$0.url] ?? -1) < (model.appSizes[$1.url] ?? -1) }
        case .status:
            ordered = apps.sorted { statusRank($0) < statusRank($1) }
        }
        return ascending ? ordered : ordered.reversed()
    }

    private func lastUsedKey(_ app: InstalledApp) -> TimeInterval {
        (model.appLastUsed[app.url] ?? nil)?.timeIntervalSince1970 ?? -1
    }

    private func statusRank(_ app: InstalledApp) -> Int {
        if model.isAppRunning(app) { return 0 }
        if !app.isWritable { return 1 }
        return 2
    }

    private func toggleSort(_ column: AppSort) {
        if sort == column { ascending.toggle() } else { sort = column; ascending = true }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Spacing.s3) {
                ForEach(sortedApps) { app in
                    AppCell(app: app)
                }
            }
            .padding(.horizontal, Metrics.widePageMargin)
            .padding(.bottom, Spacing.s6)
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(sortedApps) { app in
                        AppRow(app: app)
                        if app.id != sortedApps.last?.id {
                            Hairline().padding(.horizontal, Metrics.widePageMargin)
                        }
                    }
                } header: {
                    AppListHeader(sort: sort, ascending: ascending, onSort: toggleSort)
                        .background(Theme.paper)
                }
            }
        }
        .background(Theme.paper)
    }

    private var bulkBar: some View {
        if let progress = model.bulkProgress {
            return CommandBar(
                metric: "Removing \(progress.done) of \(progress.total)",
                detail: progress.current ?? "Working",
                actionTitle: "Working",
                isEnabled: false,
                isWorking: true,
                action: {})
        }
        return CommandBar(
            metric: model.markedBytes.formatted(.byteCount(style: .file)),
            detail: model.markedApps.count == 1
                ? "1 app selected" : "\(model.markedApps.count) apps selected",
            actionTitle: "Move to Trash",
            isEnabled: model.canBulkRemove,
            secondaryTitle: "Deselect",
            secondaryAction: { model.clearMarks() },
            help: "Review and move the selected apps to the Trash",
            accessibilityLabel: "Move to Trash, \(model.markedApps.count) apps",
            action: { model.beginBulkRemoval() })
    }
}

/// The sortable columns of the Applications list. Every column is sortable (repo rule).
private enum AppSort {
    case name, lastUsed, size, status
}

/// Stable column metrics shared by the header and the rows.
private enum AppColumns {
    static let mark: CGFloat = 20
    static let icon: CGFloat = 22
    static let lastUsed: CGFloat = 110
    static let size: CGFloat = 82
    static let status: CGFloat = 118
    static let open: CGFloat = 20
    static let spacing: CGFloat = Spacing.s3
}

/// The "Last used" cell, shared by the list row and the grid footer. Shows a relative date
/// when Spotlight has one, "Unknown" when it resolved with no record, and a dim placeholder
/// while the lazy lookup is still running.
private struct LastUsedText: View {
    @Environment(AppCleanerModel.self) private var model
    let url: URL

    var body: some View {
        if let entry = model.appLastUsed[url] {
            if let date = entry {
                Text(date, format: .relative(presentation: .named))
                    .foregroundStyle(Theme.inkSecondary)
                    .help(date.formatted(date: .long, time: .shortened))
            } else {
                Text("Unknown").foregroundStyle(Theme.inkSecondary)
            }
        } else {
            Text("...").foregroundStyle(Theme.inkTertiary)
        }
    }
}

private struct AppListHeader: View {
    let sort: AppSort
    let ascending: Bool
    let onSort: (AppSort) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: AppColumns.spacing) {
                Color.clear.frame(width: AppColumns.mark)
                sortButton("App", .name)
                    .frame(maxWidth: .infinity, alignment: .leading)
                sortButton("Last used", .lastUsed)
                    .frame(width: AppColumns.lastUsed, alignment: .leading)
                sortButton("Size", .size)
                    .frame(width: AppColumns.size, alignment: .trailing)
                sortButton("Status", .status)
                    .frame(width: AppColumns.status, alignment: .leading)
                Color.clear.frame(width: AppColumns.open)
            }
            .font(Typography.caption)
            .padding(.horizontal, Metrics.widePageMargin)
            .padding(.vertical, Spacing.s2)
            Hairline()
        }
    }

    private func sortButton(_ title: String, _ column: AppSort) -> some View {
        Button { onSort(column) } label: {
            HStack(spacing: 2) {
                Text(title)
                Image(systemName: ascending ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .opacity(sort == column ? 1 : 0)
            }
            .foregroundStyle(sort == column ? Theme.ink : Theme.inkSecondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Sort by \(title)")
    }
}

private struct AppRow: View {
    @Environment(AppCleanerModel.self) private var model
    let app: InstalledApp

    var body: some View {
        HStack(spacing: AppColumns.spacing) {
            Toggle(
                "Select to remove",
                isOn: Binding(
                    get: { model.markedApps.contains(app.url) },
                    set: { _ in model.toggleMark(app) })
            )
            .toggleStyle(.checkbox)
            .labelsHidden()
            .frame(width: AppColumns.mark)
            .accessibilityLabel("Select \(app.name) to remove")
            Image(nsImage: IconCache.icon(for: app.url))
                .resizable()
                .frame(width: AppColumns.icon, height: AppColumns.icon)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .font(Typography.row)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(app.vendorLabel ?? "Unknown developer")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            LastUsedText(url: app.url)
                .font(Typography.row)
                .lineLimit(1)
                .frame(width: AppColumns.lastUsed, alignment: .leading)
            Text(model.appSizes[app.url].map { $0.formatted(.byteCount(style: .file)) } ?? "n/a")
                .font(Typography.row)
                .monospacedDigit()
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
                .frame(width: AppColumns.size, alignment: .trailing)
            status
                .frame(width: AppColumns.status, alignment: .leading)
            Button {
                model.select(app)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.inkTertiary)
            }
            .buttonStyle(.plain)
            .frame(width: AppColumns.open)
            .help("Show files left by this app")
            .accessibilityLabel("Show files left by \(app.name)")
        }
        .padding(.vertical, Spacing.s1)
        .padding(.horizontal, Metrics.widePageMargin)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.select(app) }
        .contextMenu { appContextMenu(for: app, model: model) }
    }

    @ViewBuilder private var status: some View {
        if model.isAppRunning(app) {
            StatusLabel(
                text: "Open now", systemImage: "bolt.fill", tone: .amber,
                help: "\(app.name) is open. Quit it before removing.")
        } else if !app.isWritable {
            StatusLabel(
                text: "Needs admin", systemImage: "lock.fill", tone: .amber,
                help: "An administrator must remove this app.")
        } else {
            Color.clear.frame(height: 1)
        }
    }
}

private struct AppCell: View {
    @Environment(AppCleanerModel.self) private var model
    let app: InstalledApp
    @State private var hovering = false

    private var marked: Bool { model.markedApps.contains(app.url) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(spacing: Spacing.s2) {
                Toggle(
                    "Select to remove",
                    isOn: Binding(
                        get: { marked },
                        set: { _ in model.toggleMark(app) })
                )
                .toggleStyle(.checkbox)
                .labelsHidden()
                .accessibilityLabel("Select \(app.name) to remove")
                Spacer()
                if model.isAppRunning(app) {
                    StatusLabel(text: "Open now", systemImage: "bolt.fill", tone: .amber)
                } else if !app.isWritable {
                    StatusLabel(text: "Needs admin", systemImage: "lock.fill", tone: .amber)
                }
            }
            Button {
                model.select(app)
            } label: {
                VStack(spacing: Spacing.s2) {
                    Image(nsImage: IconCache.icon(for: app.url))
                        .resizable()
                        .frame(width: 48, height: 48)
                    Text(app.name)
                        .font(Typography.row)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Text(app.vendorLabel ?? "Unknown developer")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                    Text(model.appSizes[app.url].map { $0.formatted(.byteCount(style: .file)) } ?? "n/a")
                        .font(Typography.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.inkSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.s3)
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.s3)
        .background(Theme.paperRaised, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    marked ? Theme.accent : (hovering ? Theme.inkTertiary : Theme.hairline),
                    lineWidth: marked ? 2 : 1)
        }
        .onHover { hovering = $0 }
        .contextMenu { appContextMenu(for: app, model: model) }
    }
}

extension View {
    @ViewBuilder
    fileprivate func appContextMenu(for app: InstalledApp, model: AppCleanerModel) -> some View {
        contextMenu {
            Button("Show files left by this app", systemImage: "list.bullet.rectangle") {
                model.select(app)
            }
            Button("Open", systemImage: "arrow.up.forward.app") {
                NSWorkspace.shared.open(app.url)
            }
            Button("Reveal in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([app.url])
            }
            Divider()
            Button(
                model.markedApps.contains(app.url) ? "Deselect" : "Select to remove",
                systemImage: model.markedApps.contains(app.url) ? "minus.circle" : "checkmark.circle"
            ) {
                model.toggleMark(app)
            }
        }
    }
}
