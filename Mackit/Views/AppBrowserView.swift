import AppKit
import MackitCore
import SwiftUI

/// The uninstall destination: the inventory (grid or list, searchable) plus the bulk
/// flow. Opening one app pushes the review surface; marking several apps opens the
/// bulk pass. The confirm and summary sheets attach here — not to the pushed detail —
/// so the summary survives the pop that follows a completed removal.
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
        .sheet(isPresented: selectionConfirmBinding) {
            AppUninstallConfirmSheet()
        }
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

    /// The push edge. Selecting an app loads its components; popping clears the
    /// selection through the model, cancelling any in-flight scan.
    private var selectionBinding: Binding<URL?> {
        Binding(
            get: { model.selectedAppID },
            set: { id in
                model.select(id.flatMap { id in model.apps.first { $0.url == id } })
            })
    }

    private var selectionConfirmBinding: Binding<Bool> {
        Binding(
            get: { model.showConfirm && model.selectedApp != nil },
            set: { model.showConfirm = $0 })
    }

    private var bulkConfirmBinding: Binding<Bool> {
        Binding(
            get: { model.showBulkConfirm && !model.markedApps.isEmpty },
            set: { model.showBulkConfirm = $0 })
    }
}

/// The app inventory: every installed app as a grid cell or list row, searchable by
/// name and bundle ID. Void states: skeleton while reading, empty when nothing was
/// found, filtered empty when the search misses.
struct AppBrowserView: View {
    @Environment(AppCleanerModel.self) private var model
    let onDone: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 170), spacing: 14)]

    var body: some View {
        @Bindable var model = model
        Group {
            if model.isLoadingApps {
                skeleton
            } else if model.apps.isEmpty {
                ContentUnavailableView(
                    "No applications found",
                    systemImage: "app.badge.minus",
                    description: Text("Grant Full Disk Access, then reload."))
            } else if model.filteredApps.isEmpty {
                ContentUnavailableView(
                    "No matches",
                    systemImage: "magnifyingglass",
                    description: Text("No application matches \"\(model.query)\"."))
            } else {
                switch model.style {
                case .grid: browserGrid
                case .list: browserList
                }
            }
        }
        .navigationTitle("Applications")
        .navigationSubtitle(appSubtitle)
        .searchable(text: $model.query, placement: .toolbar, prompt: "Search apps")
        .safeAreaInset(edge: .bottom) {
            if model.isBulkRemoving || !model.markedApps.isEmpty {
                BulkActionBarView()
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
                        Image(systemName: style.symbol).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("Show the inventory as a grid or a list")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.load()
                } label: {
                    Label("Reload Apps", systemImage: "arrow.clockwise")
                }
                .disabled(model.isLoadingApps)
                .help("Read the applications folder again")
            }
        }
    }

    private var appSubtitle: String {
        model.apps.isEmpty ? "Installed apps" : "\(model.apps.count) installed"
    }

    private var browserGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(model.filteredApps) { app in
                    AppCell(app: app)
                }
            }
            .padding(20)
        }
    }

    private var browserList: some View {
        List {
            ForEach(model.filteredApps) { app in
                AppRow(app: app)
            }
        }
        .alternatingRowBackgrounds(.disabled)
    }

    /// Loading renders the exact shape the chosen style will occupy — flat skeletons.
    @ViewBuilder private var skeleton: some View {
        switch model.style {
        case .grid:
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(0..<12, id: \.self) { _ in
                        VStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.quaternary)
                                .frame(width: 52, height: 52)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.quaternary)
                                .frame(width: 96, height: 9)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.quaternary.opacity(0.6))
                                .frame(width: 64, height: 8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                    }
                }
                .padding(20)
            }
            .redacted(reason: .placeholder)
            .allowsHitTesting(false)
        case .list:
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(0..<10, id: \.self) { _ in
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 14, height: 14)
                            RoundedRectangle(cornerRadius: 6).fill(.quaternary).frame(width: 24, height: 24)
                            RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 180, height: 9)
                            Spacer()
                            RoundedRectangle(cornerRadius: 4).fill(.quaternary.opacity(0.6)).frame(width: 70, height: 8)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                    }
                }
            }
            .redacted(reason: .placeholder)
            .allowsHitTesting(false)
        }
    }
}

/// One installed app in the grid. A running app shows an orange dot, an admin-only
/// app a lock, the vendor under the name, and size and location on the last line. A
/// circle-check in the corner marks the app for bulk removal. Neither the running
/// state nor the lock blocks marking — the confirm sheet and the core carry the
/// consequences.
private struct AppCell: View {
    @Environment(AppCleanerModel.self) private var model
    let app: InstalledApp

    @State private var hovering = false

    private var marked: Bool { model.markedApps.contains(app.url) }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                model.select(app)
            } label: {
                VStack(spacing: 9) {
                    Image(nsImage: IconCache.icon(for: app.url))
                        .resizable()
                        .frame(width: 52, height: 52)
                        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                    Text(app.name)
                        .font(.callout)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.center)
                    Text(app.vendorLabel ?? app.bundleID ?? " ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1, reservesSpace: true)
                    HStack(spacing: 5) {
                        if model.isAppRunning(app) {
                            Circle()
                                .fill(.orange)
                                .frame(width: 6, height: 6)
                                .help("\(app.name) is running — quit it to remove it")
                        }
                        if !app.isWritable {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .help("An administrator must remove this app")
                        }
                        Text(sizeLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(model.locationLabel(app))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .padding(.top, 6)
                .background(
                    .quaternary.opacity(hovering ? 0.6 : 0.0001),
                    in: RoundedRectangle(cornerRadius: 16)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            Color.accentColor.opacity(marked ? 0.55 : 0), lineWidth: 1.5)
                }
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .contextMenu { appContextMenu(for: app, model: model) }

            Button {
                model.toggleMark(app)
            } label: {
                Image(systemName: marked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(marked ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                    .background(.thinMaterial, in: .circle)
                    .padding(7)
            }
            .buttonStyle(.plain)
            .opacity(marked ? 1 : (hovering ? 0.85 : 0))
            .help(marked ? "Remove from the bulk selection" : "Mark for bulk removal")
        }
    }

    private var sizeLabel: String {
        model.appSizes[app.url].map { $0.formatted(.byteCount(style: .file)) } ?? "—"
    }
}

/// One installed app in the list: marking checkbox, identity, facts right-aligned.
private struct AppRow: View {
    @Environment(AppCleanerModel.self) private var model
    let app: InstalledApp

    var body: some View {
        HStack(spacing: 10) {
            Toggle(
                "Mark for bulk removal",
                isOn: Binding(
                    get: { model.markedApps.contains(app.url) },
                    set: { _ in model.toggleMark(app) })
            )
            .toggleStyle(.checkbox)
            .labelsHidden()
            .help("Mark for bulk removal")
            Image(nsImage: IconCache.icon(for: app.url))
                .resizable()
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).lineLimit(1)
                Text(app.bundleID ?? "No bundle identifier")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            if model.isAppRunning(app) {
                Circle()
                    .fill(.orange)
                    .frame(width: 7, height: 7)
                    .help("\(app.name) is running — quit it to remove it")
            }
            if !app.isWritable {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("An administrator must remove this app")
            }
            if let vendor = app.vendorLabel {
                Text(vendor)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 110, alignment: .trailing)
            }
            Text(model.locationLabel(app))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 130, alignment: .trailing)
            if let version = app.version {
                Text(version)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 70, alignment: .trailing)
            }
            Text(sizeLabel)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { model.select(app) }
        .contextMenu { appContextMenu(for: app, model: model) }
    }

    private var sizeLabel: String {
        model.appSizes[app.url].map { $0.formatted(.byteCount(style: .file)) } ?? "—"
    }
}

/// Actions available from the cell or row: go deeper, act on the bundle, or queue the
/// app for the bulk pass.
extension View {
    @ViewBuilder
    fileprivate func appContextMenu(for app: InstalledApp, model: AppCleanerModel) -> some View {
        contextMenu {
            Button("Show Related Files", systemImage: "list.bullet.rectangle") {
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
                model.markedApps.contains(app.url) ? "Unmark" : "Mark for Removal",
                systemImage: model.markedApps.contains(app.url) ? "minus.circle" : "checkmark.circle"
            ) {
                model.toggleMark(app)
            }
        }
    }
}

/// Floating glass bar at the bottom of the browser: what is marked, and the bulk
/// Remove button. While a bulk pass runs it becomes a progress line instead — the
/// grid keeps scrolling, the pass never blocks it.
private struct BulkActionBarView: View {
    @Environment(AppCleanerModel.self) private var model

    var body: some View {
        Group {
            if let progress = model.bulkProgress {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Removing \(progress.done) of \(progress.total)…")
                        .monospacedDigit()
                    if let current = progress.current {
                        Text(current)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .padding(.leading, 18)
                .padding(.trailing, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 16)
            } else {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(model.markedBytes.formatted(.byteCount(style: .file)))
                            .font(.headline)
                            .monospacedDigit()
                        Text(
                            model.markedApps.count == 1
                                ? "1 app selected" : "\(model.markedApps.count) apps selected"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Button("Clear") { model.clearMarks() }
                        .disabled(!model.canBulkRemove)
                    Button("Remove…", systemImage: "trash") { model.beginBulkRemoval() }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                        .disabled(!model.canBulkRemove)
                        .keyboardShortcut(.delete, modifiers: .command)
                        .help("Review and move the marked apps to the Trash (Command-Delete)")
                }
                .padding(.leading, 18)
                .padding(.trailing, 8)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 16)
            }
        }
    }
}
