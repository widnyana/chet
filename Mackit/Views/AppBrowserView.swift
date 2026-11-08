import AppKit
import MackitCore
import SwiftUI

/// The uninstall destination: a searchable grid of installed apps that pushes the
/// detail view for one app. The confirm and summary sheets attach here — not to the
/// pushed detail — so the summary survives the pop that follows a completed removal.
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
}

/// The app inventory: every installed app as a grid cell, searchable by name and
/// bundle ID. Void states: skeleton while reading, empty when nothing was found,
/// filtered empty when the search misses.
struct AppBrowserView: View {
    @Environment(AppCleanerModel.self) private var model

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 14)]

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
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(model.filteredApps) { app in
                            AppCell(app: app) {
                                model.select(app)
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle("Applications")
        .navigationSubtitle(appSubtitle)
        .searchable(text: $model.query, placement: .toolbar, prompt: "Search apps")
        .toolbar {
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

    /// Loading renders the exact shape the grid will occupy — flat skeleton cells.
    private var skeleton: some View {
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
    }
}

/// One installed app. A running app shows an orange dot; an admin-only app shows a
/// lock. Neither blocks browsing — the detail view carries the warnings.
private struct AppCell: View {
    @Environment(AppCleanerModel.self) private var model
    let app: InstalledApp
    let open: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            VStack(spacing: 9) {
                Image(nsImage: IconCache.icon(for: app.url))
                    .resizable()
                    .frame(width: 52, height: 52)
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                Text(app.name)
                    .font(.callout)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.center)
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
                    if let version = app.version {
                        Text(version)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
                .frame(height: 14)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                .quaternary.opacity(hovering ? 0.6 : 0.0001),
                in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
