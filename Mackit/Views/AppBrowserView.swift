import AppKit
import MackitCore
import SwiftUI

/// The uninstall destination: the inventory (list or grid) plus the bulk flow.
/// Opening one app pushes the review surface; marking several apps opens the
/// bulk pass. The sheets attach here so the summary survives the pop.
struct UninstallWorkspace: View {
    @Environment(AppCleanerModel.self) private var model
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            AppBrowserView(onDone: onDone)
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
    let onDone: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 164), spacing: Spacing.s3)]

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            PageHeader(
                title: "Applications",
                subtitle: subtitle,
                metric: nil
            )
            .padding(.horizontal, Metrics.widePageMargin)
            .padding(.top, Spacing.s6)
            .padding(.bottom, Spacing.s3)
            if model.isLoadingApps {
                LoadingStateView(message: "Reading applications")
                    .padding(.horizontal, Metrics.widePageMargin)
                Spacer()
            } else if model.apps.isEmpty {
                EmptyStateView(
                    title: "No applications found",
                    message: "Check that the Applications folder is readable, then reload.",
                    actionTitle: "Reload",
                    action: { model.load() }
                )
                .padding(.horizontal, Metrics.widePageMargin)
                Spacer()
            } else if model.filteredApps.isEmpty {
                EmptyStateView(
                    title: "No matches",
                    message: "No application matches \"\(model.query)\".",
                    actionTitle: "Clear search",
                    action: { model.query = "" }
                )
                .padding(.horizontal, Metrics.widePageMargin)
                Spacer()
            } else {
                switch model.style {
                case .grid: grid
                case .list: list
                }
            }
        }
        .background(Theme.paper)
        .navigationTitle("Applications")
        .searchable(text: $model.query, placement: .toolbar, prompt: "Search apps")
        .safeAreaInset(edge: .bottom) {
            if model.isBulkRemoving || !model.markedApps.isEmpty {
                bulkBar
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Done", action: onDone)
                    .help("Back to the Overview")
            }
            ToolbarItem(placement: .primaryAction) {
                Picker("Layout", selection: $model.style) {
                    ForEach(AppBrowserStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("Show the inventory as a list or a grid")
            }
            ToolbarItem(placement: .primaryAction) {
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
        if model.apps.isEmpty {
            return model.hasFullDiskAccess
                ? "Installed applications"
                : "Installed applications. Some related files may be hidden without Full Disk Access."
        }
        if model.markedApps.isEmpty {
            return "\(model.apps.count) installed"
        }
        return "\(model.apps.count) installed, \(model.markedApps.count) marked"
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Spacing.s3) {
                ForEach(model.filteredApps) { app in
                    AppCell(app: app)
                }
            }
            .padding(.horizontal, Metrics.widePageMargin)
            .padding(.bottom, Spacing.s6)
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            AppListHeader()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.filteredApps) { app in
                        AppRow(app: app)
                        if app.id != model.filteredApps.last?.id {
                            Hairline().padding(.horizontal, Metrics.widePageMargin)
                        }
                    }
                }
            }
            .background(Theme.paper)
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
            detail: model.markedApps.count == 1
                ? "1 app marked" : "\(model.markedApps.count) apps marked",
            actionTitle: "Remove",
            isEnabled: model.canBulkRemove,
            secondaryTitle: "Clear",
            secondaryAction: { model.clearMarks() },
            help: "Review and move the marked apps to the Trash",
            action: { model.beginBulkRemoval() })
    }
}

/// Stable column metrics shared by the header and the rows.
private enum AppColumns {
    static let mark: CGFloat = 20
    static let icon: CGFloat = 22
    static let location: CGFloat = 130
    static let version: CGFloat = 68
    static let size: CGFloat = 82
    static let status: CGFloat = 118
    static let open: CGFloat = 20
    static let spacing: CGFloat = 10
}

private struct AppListHeader: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: AppColumns.spacing) {
                Color.clear.frame(width: AppColumns.mark)
                Text("Application")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Location").frame(width: AppColumns.location, alignment: .leading)
                Text("Version").frame(width: AppColumns.version, alignment: .trailing)
                Text("Size").frame(width: AppColumns.size, alignment: .trailing)
                Text("Status").frame(width: AppColumns.status, alignment: .leading)
                Color.clear.frame(width: AppColumns.open)
            }
            .font(Typography.caption)
            .foregroundStyle(Theme.inkSecondary)
            .padding(.horizontal, Metrics.widePageMargin)
            .padding(.vertical, Spacing.s2)
            Hairline()
        }
    }
}

private struct AppRow: View {
    @Environment(AppCleanerModel.self) private var model
    let app: InstalledApp

    var body: some View {
        HStack(spacing: AppColumns.spacing) {
            Toggle(
                "Mark for removal",
                isOn: Binding(
                    get: { model.markedApps.contains(app.url) },
                    set: { _ in model.toggleMark(app) })
            )
            .toggleStyle(.checkbox)
            .labelsHidden()
            .frame(width: AppColumns.mark)
            .accessibilityLabel("Mark \(app.name) for removal")
            Image(nsImage: IconCache.icon(for: app.url))
                .resizable()
                .frame(width: AppColumns.icon, height: AppColumns.icon)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .font(Typography.row)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(app.bundleID ?? "No bundle identifier")
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
                .frame(width: AppColumns.location, alignment: .leading)
            Text(app.version ?? " ")
                .font(Typography.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
                .frame(width: AppColumns.version, alignment: .trailing)
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
            .help("Show related files")
            .accessibilityLabel("Show related files for \(app.name)")
        }
        .padding(.vertical, 3)
        .padding(.horizontal, Metrics.widePageMargin)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.select(app) }
        .contextMenu { appContextMenu(for: app, model: model) }
    }

    @ViewBuilder private var status: some View {
        if model.isAppRunning(app) {
            StatusLabel(
                text: "Running", systemImage: "bolt.fill", tone: .amber,
                help: "\(app.name) is running. Quit it before removing.")
        } else if !app.isWritable {
            StatusLabel(
                text: "Admin", systemImage: "lock.fill", tone: .amber,
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
                    "Mark for removal",
                    isOn: Binding(
                        get: { marked },
                        set: { _ in model.toggleMark(app) })
                )
                .toggleStyle(.checkbox)
                .labelsHidden()
                .accessibilityLabel("Mark \(app.name) for removal")
                Spacer()
                if model.isAppRunning(app) {
                    StatusLabel(text: "Running", systemImage: "bolt.fill", tone: .amber)
                } else if !app.isWritable {
                    StatusLabel(text: "Admin", systemImage: "lock.fill", tone: .amber)
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
                    Text(app.vendorLabel ?? app.bundleID ?? " ")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                    HStack(spacing: Spacing.s1) {
                        Text(model.appSizes[app.url].map { $0.formatted(.byteCount(style: .file)) } ?? "n/a")
                            .monospacedDigit()
                        Text("·")
                            .foregroundStyle(Theme.inkTertiary)
                        Text(model.locationLabel(app))
                            .lineLimit(1)
                    }
                    .font(Typography.caption)
                    .foregroundStyle(Theme.inkSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.s3)
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.s3)
        .background(Theme.paperRaised, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    marked ? Theme.accent : (hovering ? Theme.inkTertiary : Theme.hairline),
                    lineWidth: marked ? 1.5 : 1)
        }
        .onHover { hovering = $0 }
        .contextMenu { appContextMenu(for: app, model: model) }
    }
}

extension View {
    @ViewBuilder
    fileprivate func appContextMenu(for app: InstalledApp, model: AppCleanerModel) -> some View {
        contextMenu {
            Button("Show related files", systemImage: "list.bullet.rectangle") {
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
                model.markedApps.contains(app.url) ? "Unmark" : "Mark for removal",
                systemImage: model.markedApps.contains(app.url) ? "minus.circle" : "checkmark.circle"
            ) {
                model.toggleMark(app)
            }
        }
    }
}
