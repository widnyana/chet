import AppKit
import MackitCore
import SwiftUI

struct AppCleanerDetailView: View {
    @Environment(AppCleanerModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if let app = model.selectedApp {
                detail(app)
            } else {
                ContentUnavailableView(
                    "Choose an app",
                    systemImage: "app.badge.minus",
                    description: Text("Select an application in the sidebar to see its files."))
            }
        }
        .navigationTitle(model.selectedApp?.name ?? "Uninstall")
        .navigationSubtitle(subtitle)
        .sheet(isPresented: $model.showConfirm) {
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
        .onAppear { model.refreshRunningState() }
    }

    private var subtitle: String {
        guard let app = model.selectedApp else {
            return "Move an app and its Library files to the Trash"
        }
        return "\(app.version.map { "Version \($0)" } ?? "Unknown version") · \(app.bundleID ?? "no bundle ID")"
    }

    private func detail(_ app: InstalledApp) -> some View {
        @Bindable var model = model
        return VStack(spacing: 0) {
            header(app, selected: $model.appSelected)
            if model.isRunning { runningWarning(app) }
            if !app.isWritable { adminWarning(app) }
            Divider()
            if model.isLoadingDetail {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Looking for related files…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.components.isEmpty {
                ContentUnavailableView(
                    "No related files",
                    systemImage: "checkmark.seal",
                    description: Text(
                        model.hasFullDiskAccess
                            ? "Mackit found no Library data for this app. The app bundle can still be removed."
                            : "Mackit found no Library data. Some folders are hidden without Full Disk Access."))
            } else {
                componentList
            }
        }
        .safeAreaInset(edge: .bottom) {
            ActionBarView()
        }
    }

    private func header(_ app: InstalledApp, selected: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(nsImage: IconCache.icon(for: app.url))
                .resizable()
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(app.name).font(.title2.bold())
                    if model.isRunning {
                        Label("Running", systemImage: "bolt.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                    if !app.isWritable {
                        Label("Needs administrator", systemImage: "lock.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
                Text(app.bundleID ?? "No bundle identifier")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text(app.url.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                HStack(spacing: 14) {
                    Label(app.version ?? "Unknown version", systemImage: "number")
                    Label(
                        model.isLoadingDetail
                            ? "Measuring…" : model.appBytes.formatted(.byteCount(style: .file)),
                        systemImage: "internaldrive")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                Toggle("Remove app bundle", isOn: selected)
                    .toggleStyle(.checkbox)
                    .disabled(model.isRunning || !app.isWritable)
                    .help(
                        app.isWritable
                            ? "Move the app itself to the Trash"
                            : "An administrator must remove this app")
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([app.url])
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
        .padding(20)
    }

    private func runningWarning(_ app: InstalledApp) -> some View {
        Label(
            "Quit \(app.name) before removing it. A running app can write its data back after the move.",
            systemImage: "exclamationmark.triangle.fill"
        )
        .font(.callout)
        .foregroundStyle(.orange)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.orange.opacity(0.12))
    }

    private func adminWarning(_ app: InstalledApp) -> some View {
        Label(
            "Mackit cannot move this app without administrator rights. Related files in your home folder can still be removed.",
            systemImage: "lock.fill"
        )
        .font(.callout)
        .foregroundStyle(.orange)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.orange.opacity(0.12))
    }

    private var componentList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(
                    "\(model.selectedComponentList.count) of \(model.components.count) selected, "
                        + model.selectedComponentList.reduce(0) { $0 + $1.bytes }
                        .formatted(.byteCount(style: .file))
                )
                .monospacedDigit()
                .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button("Exact Matches Only", systemImage: "checkmark.seal") { model.selectExact() }
                    Button("All Selectable", systemImage: "checklist") { model.selectAllSelectable() }
                    Button("None", systemImage: "circle") { model.clearComponents() }
                } label: {
                    Label("Select", systemImage: "checklist")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.4))
            List {
                ForEach(grouped, id: \.kind) { group in
                    Section {
                        ForEach(group.items) { component in
                            AppComponentRow(component: component)
                        }
                    } header: {
                        HStack {
                            Text(group.kind.title)
                            Spacer()
                            Text(group.items.reduce(0) { $0 + $1.bytes }.formatted(.byteCount(style: .file)))
                                .monospacedDigit()
                        }
                    }
                }
            }
            .alternatingRowBackgrounds(.disabled)
        }
    }

    private var grouped: [(kind: AppComponentKind, items: [AppComponent])] {
        let order = AppComponentKind.allCases
        return Dictionary(grouping: model.components, by: \.kind)
            .map { (kind: $0.key, items: $0.value.sorted { $0.bytes > $1.bytes }) }
            .sorted {
                (order.firstIndex(of: $0.kind) ?? Int.max) < (order.firstIndex(of: $1.kind) ?? Int.max)
            }
    }
}

private struct AppComponentRow: View {
    @Environment(AppCleanerModel.self) private var model
    let component: AppComponent

    var body: some View {
        let selected = model.selectedComponents.contains(component.url)
        HStack(spacing: 10) {
            Toggle(
                "Remove", isOn: Binding(get: { selected }, set: { model.setComponent(component, $0) })
            )
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(!component.isSelectable)
            Image(nsImage: IconCache.icon(for: component.url))
                .resizable()
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(component.url.lastPathComponent)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(DisplayName.location(of: component.url))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    AppOwnershipBadge(component: component)
                }
            }
            Spacer()
            Text(component.bytes.formatted(.byteCount(style: .file)))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([component.url])
            }
        }
        .help(component.url.path)
    }
}

private struct AppOwnershipBadge: View {
    let component: AppComponent

    var body: some View {
        switch component.ownership {

        case .exclusive:
            badge("Exact", .green, "checkmark.seal.fill")
        case .probable:
            badge("Name match", .orange, "questionmark.circle")
        case .shared:
            badge("Shared", .secondary, "person.2")
        case .privileged:
            badge("Admin", .orange, "lock.fill")
        case .systemProtected:
            badge("Protected", .red, "shield.lefthalf.filled")
        }
    }

    private func badge(_ title: String, _ color: Color, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(color.opacity(0.12), in: Capsule())
            .help(component.ownership.title)
    }
}

private struct ActionBarView: View {
    @Environment(AppCleanerModel.self) private var model

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                Text(model.selectedBytes.formatted(.byteCount(style: .file)))
                    .font(.headline)
                    .monospacedDigit()
                Text(
                    model.selectedCount == 1
                        ? "1 item selected" : "\(model.selectedCount) items selected"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Button("Remove", systemImage: "trash") { model.beginRemoval() }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(!model.canRemove)
                .keyboardShortcut(.delete, modifiers: .command)
                .help("Review and move the selected items to the Trash (Command-Delete)")
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 16)
    }
}
