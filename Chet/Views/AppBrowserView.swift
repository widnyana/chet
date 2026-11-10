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

    private let columns = [GridItem(.adaptive(minimum: Metrics.gridCellMinWidth), spacing: Spacing.s3)]
    @State private var sort: AppSort = .name
    @State private var ascending = true

    var body: some View {
        @Bindable var model = model
        PageScreen(
            scrolls: false,
            header: {
                PageHeader(
                    title: "Apps",
                    subtitle: subtitle,
                    metric: nil
                )
                .accessibilityIdentifier("apps.header")
            },
            content: {
                if model.isLoadingApps && model.apps.isEmpty {
                    LoadingStateView(message: "Reading applications")
                        .pageHorizontalPadding()
                } else if let error = model.loadError, model.apps.isEmpty {
                    ErrorStateView(
                        title: "The applications folder could not be read.",
                        message: "Check Full Disk Access, then reload.",
                        actionTitle: "Reload",
                        action: { model.load() }
                    )
                    .help(error)
                    .pageHorizontalPadding()
                } else if model.apps.isEmpty {
                    noApps
                        .pageHorizontalPadding()
                } else if model.filteredApps.isEmpty {
                    EmptyStateView(
                        title: "No application matches \"\(model.query)\"",
                        message: "Clear the search to see all apps.",
                        actionTitle: "Clear search",
                        action: { model.query = "" }
                    )
                    .pageHorizontalPadding()
                } else {
                    if let error = model.loadError {
                        StatusLabel(
                            text: "Some application folders could not be read.",
                            systemImage: "exclamationmark.triangle",
                            tone: .amber,
                            help: error
                        )
                        .pageHorizontalPadding()
                        .padding(.bottom, Spacing.s2)
                    }
                    switch model.style {
                    case .grid: grid
                    case .list: list
                    }
                }
            },
            bar: { bulkBar }
        )
        .searchable(text: $model.query, placement: .toolbar, prompt: "Search apps")
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
        "\(model.apps.count) installed, \(model.markedApps.count) marked"
    }

    @ViewBuilder private var noApps: some View {
        if model.hasFullDiskAccess {
            EmptyStateView(
                title: "No applications found",
                message: "Try reading the Applications folder again.",
                actionTitle: "Reload",
                action: { model.load() })
        } else {
            EmptyStateView(
                title: "No applications found",
                message: "If this is unexpected, check Full Disk Access.",
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
        case .location:
            ordered = apps.sorted {
                let left = model.locationLabel($0)
                let right = model.locationLabel($1)
                return left == right
                    ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                    : left.localizedStandardCompare(right) == .orderedAscending
            }
        case .version:
            ordered = apps.sorted {
                ($0.version ?? "").localizedStandardCompare($1.version ?? "") == .orderedAscending
            }
        case .size:
            ordered = apps.sorted { (model.appSizes[$0.url] ?? -1) < (model.appSizes[$1.url] ?? -1) }
        case .status:
            ordered = apps.sorted { statusRank($0) < statusRank($1) }
        }
        return ascending ? ordered : ordered.reversed()
    }

    private func statusRank(_ app: InstalledApp) -> Int {
        if model.isAppRunning(app) { return 0 }
        if !app.isWritable { return 1 }
        return 2
    }

    private func toggleSort(_ column: AppSort) {
        if sort == column {
            ascending.toggle()
        } else {
            sort = column
            ascending = true
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Spacing.s3) {
                ForEach(sortedApps) { app in
                    AppCell(app: app)
                }
            }
            .pageHorizontalPadding()
            .padding(.bottom, Spacing.s6)
        }
    }

    private var list: some View {
        ColumnTable(items: sortedApps) {
            AppListHeader(sort: sort, ascending: ascending, onSort: toggleSort)
        } row: { app in
            AppRow(app: app)
        }
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
            detail: model.markedApps.isEmpty
                ? "No apps selected"
                : (model.markedApps.count == 1
                    ? "1 app selected" : "\(model.markedApps.count) apps selected"),
            actionTitle: "Remove",
            isEnabled: model.canBulkRemove,
            secondaryTitle: model.markedApps.isEmpty ? nil : "Clear",
            secondaryAction: model.markedApps.isEmpty ? nil : { model.clearMarks() },
            help: "Review and move the selected apps to the Trash",
            accessibilityLabel: "Remove, \(model.markedApps.count) apps",
            disabledReason: model.markedApps.isEmpty ? "Select an app to remove." : nil,
            action: { model.beginBulkRemoval() })
    }
}

/// The sortable columns of the Applications list. Every column is sortable (repo rule).
private enum AppSort {
    case name, location, version, size, status
}

private struct AppListHeader: View {
    let sort: AppSort
    let ascending: Bool
    let onSort: (AppSort) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: ColumnRegistry.spacing) {
                Color.clear.frame(width: ColumnRegistry.spec(.mark).width)
                Color.clear.frame(width: ColumnRegistry.spec(.icon).width)
                sortButton("Name", .name)
                    .frame(maxWidth: .infinity, alignment: .leading)
                sortButton("Location", .location)
                    .frame(width: ColumnRegistry.spec(.location).width, alignment: .leading)
                sortButton("Version", .version)
                    .frame(width: ColumnRegistry.spec(.version).width, alignment: .leading)
                sortButton("Size", .size)
                    .frame(width: ColumnRegistry.spec(.size).width, alignment: .trailing)
                sortButton("Status", .status)
                    .frame(width: ColumnRegistry.spec(.status).width, alignment: .leading)
            }
            .font(Typography.caption)
            .pageHorizontalPadding()
            .padding(.vertical, Spacing.s2)
            Hairline()
        }
    }

    private func sortButton(_ title: String, _ column: AppSort) -> some View {
        SortColumnButton(
            title: title,
            isActive: sort == column,
            ascending: ascending
        ) {
            onSort(column)
        }
    }
}

private struct AppRow: View {
    @Environment(AppCleanerModel.self) private var model
    let app: InstalledApp

    var body: some View {
        TableRow(
            isHighlighted: model.markedApps.contains(app.url),
            onOpen: { model.select(app) },
            content: {
                HStack(spacing: ColumnRegistry.spacing) {
                    RowCheckbox(
                        isOn: Binding(
                            get: { model.markedApps.contains(app.url) },
                            set: { _ in model.toggleMark(app) }),
                        label: "Select \(app.name) to remove",
                        width: ColumnRegistry.spec(.mark).width)
                    Image(nsImage: IconCache.icon(for: app.url))
                        .resizable()
                        .frame(width: ColumnRegistry.spec(.icon).width, height: ColumnRegistry.spec(.icon).width)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(app.name)
                            .font(Typography.row)
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Text(app.bundleID ?? "Unknown")
                            .font(Typography.caption)
                            .foregroundStyle(Theme.inkSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(model.locationLabel(app))
                        .font(Typography.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                        .frame(width: ColumnRegistry.spec(.location).width, alignment: .leading)
                    Text(app.version ?? "Unknown")
                        .font(Typography.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                        .frame(width: ColumnRegistry.spec(.version).width, alignment: .leading)
                    if let bytes = model.appSizes[app.url] {
                        SizeColumn(bytes: bytes, width: ColumnRegistry.spec(.size).width)
                    } else {
                        Text("Unknown")
                            .font(Typography.row)
                            .monospacedDigit()
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                            .frame(width: ColumnRegistry.spec(.size).width, alignment: .trailing)
                    }
                    status
                        .frame(width: ColumnRegistry.spec(.status).width, alignment: .leading)
                }
                .contextMenu { appContextMenu(for: app, model: model) }
            })
    }

    @ViewBuilder private var status: some View {
        if model.isAppRunning(app) {
            StatusLabel(
                text: "Running", systemImage: "bolt.fill", tone: .amber,
                help: "\(app.name) is open. Quit it before removing.")
        } else if !app.isWritable {
            StatusLabel(
                text: "Needs administrator", systemImage: "lock.fill", tone: .amber,
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

    private var identity: String {
        (app.bundleID ?? app.url.deletingPathExtension().lastPathComponent).lowercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(spacing: Spacing.s2) {
                RowCheckbox(
                    identifier: "apps.select.\(identity)",
                    isOn: Binding(get: { marked }, set: { _ in model.toggleMark(app) }),
                    label: "Select \(app.name) to remove")
                Spacer()
                if model.isAppRunning(app) {
                    StatusLabel(text: "Running", systemImage: "bolt.fill", tone: .amber)
                } else if !app.isWritable {
                    StatusLabel(text: "Needs administrator", systemImage: "lock.fill", tone: .amber)
                }
            }
            RowActionButton(
                help: "Show files left by \(app.name)",
                accessibilityLabel: "Show files left by \(app.name)",
                action: { model.select(app) },
                label: {
                    VStack(spacing: Spacing.s2) {
                        Image(nsImage: IconCache.icon(for: app.url))
                            .resizable()
                            .frame(width: 48, height: 48)
                        Text(app.name)
                            .font(Typography.row)
                            .foregroundStyle(Theme.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                        Text(app.vendorLabel ?? "Unknown")
                            .font(Typography.caption)
                            .foregroundStyle(Theme.inkSecondary)
                            .lineLimit(1)
                        Text(
                            "\(model.appSizes[app.url].map { $0.formatted(.byteCount(style: .file)) } ?? "Unknown") · \(model.locationLabel(app))"
                        )
                        .font(Typography.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.s3)
                })
        }
        .padding(Spacing.s3)
        .background(Theme.paperRaised, in: .rect(corners: .fixed(Metrics.controlRadius)))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
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
