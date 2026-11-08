import MackitCore
import SwiftUI

struct SidebarView: View {
    @Environment(ScanModel.self) private var model
    @Environment(AppCleanerModel.self) private var appCleaner
    @Binding var selection: String?
    @Binding var mode: AppMode

    var body: some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $mode) {
                ForEach(AppMode.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .help("Choose between junk cleaning and app uninstalling")
            Divider()
            if mode == .clean {
                cleanList
            } else {
                appList
            }
        }
        .navigationSplitViewColumnWidth(min: 240, ideal: 280)
    }

    private var cleanList: some View {
        List(selection: $selection) {
            row("overview", "Overview", running: model.isScanning)
            if !model.categories.isEmpty || model.isScanning {
                Section("Reclaimable") {
                    if model.categories.isEmpty {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("Scanning…").foregroundStyle(.secondary)
                        }
                        .tag("scanning-placeholder")
                    }
                    ForEach(model.categories) { category in
                        let step = ScanStatusView.step(forCategory: category.id)
                        let running = model.isScanning && model.currentStep == step
                        let pending =
                            model.isScanning && !(model.steps.first(where: { $0.id == step })?.done ?? false)
                            && category.bytes == 0
                        row(
                            category.id, category.title,
                            trailing: category.id == "snapshots"
                                ? "\(model.snapshots.count)" : category.bytes.formatted(.byteCount(style: .file)),
                            locked: category.needsFullDiskAccess,
                            running: running, dimmed: pending)
                    }
                }
            }
            Section("Inspect") {
                row("disk-map", "Disk map")
            }
        }
    }

    private var appList: some View {
        List(selection: appSelection) {
            if appCleaner.isLoadingApps {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Reading applications…").foregroundStyle(.secondary)
                }
            } else if appCleaner.filteredApps.isEmpty {
                Text(appCleaner.query.isEmpty ? "No applications found" : "No matching applications")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appCleaner.filteredApps) { app in
                    appRow(app)
                }
            }
        }
        .searchable(text: queryBinding, placement: .sidebar, prompt: "Search apps")
    }

    private var appSelection: Binding<URL?> {
        Binding(
            get: { appCleaner.selectedAppID },
            set: { url in
                appCleaner.selectedAppID = url
                appCleaner.select(url.flatMap { id in appCleaner.apps.first { $0.url == id } })
            })
    }

    private var queryBinding: Binding<String> {
        Binding(get: { appCleaner.query }, set: { appCleaner.query = $0 })
    }

    private func appRow(_ app: InstalledApp) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: IconCache.icon(for: app.url))
                .resizable()
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).lineLimit(1)
                Text(app.bundleID ?? app.url.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if !app.isWritable {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("An administrator must remove this app")
            }
            if let version = app.version {
                Text(version)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .tag(app.url)
    }

    private func row(
        _ id: String, _ title: String, trailing: String? = nil, locked: Bool = false,
        running: Bool = false, dimmed: Bool = false
    ) -> some View {
        let style = CategoryStyle.of(id)
        return Label {
            HStack {
                Text(title).lineLimit(1)
                    .foregroundStyle(dimmed ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                if running {
                    ProgressView().controlSize(.mini)
                }
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("Some folders need Full Disk Access")
                }
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        } icon: {
            Image(systemName: style.symbol)
                .foregroundStyle(style.color)
        }
        .tag(id)
    }
}
