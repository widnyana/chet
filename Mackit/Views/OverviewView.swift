import Charts
import MackitCore
import SwiftUI

/// Start screen: disk usage, scan progress, and what can be cleaned per category.
struct OverviewView: View {
    @Environment(ScanModel.self) private var model
    @Binding var selection: String?
    let onClean: () -> Void
    let onUninstall: () -> Void
    @State private var pickedTitle: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DiskBar(reclaimable: model.totalBytes)
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: .rect(cornerRadius: 22))
                uninstallDoor
                if model.isScanning {
                    progress
                } else if model.lastScan == nil {
                    hero
                } else {
                    results
                }
            }
            .padding(28)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Overview")
        .onChange(of: pickedTitle) { _, title in
            if let id = model.categories.first(where: { $0.title == title })?.id { selection = id }
        }
    }

    /// The one door into the uninstaller. Present in every overview state — removing
    /// apps does not depend on a scan. Same card grammar as every card here: 24 pt
    /// padding, 22 pt corners, bare tinted symbol, bold action title, neutral chip.
    private var uninstallDoor: some View {
        Button(action: onUninstall) {
            HStack(spacing: 18) {
                Image(systemName: "app.dashed")
                    .font(.system(size: 28))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Uninstall apps")
                        .font(.title3.bold())
                    Text("Remove an app together with everything it left behind.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Text("Open")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(.quaternary.opacity(0.9), in: .capsule)
            }
            .padding(24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .help("Open the app uninstaller")
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Find what you can safely remove")
                .font(.title.bold())
            Text(
                "Mackit looks through caches, logs, developer data, old installers, duplicates and similar photos. Nothing is removed until you confirm."
            )
            .foregroundStyle(.secondary)
            Button("Scan This Mac", systemImage: "magnifyingglass") { model.scan() }
                .buttonStyle(.glassProminent)
                .controlSize(.extraLarge)
                .padding(.top, 6)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ProgressView().controlSize(.small)
                Text("Scanning").font(.title2.bold())
                Spacer()
                Text("\(model.totalBytes.formatted(.byteCount(style: .file))) found so far")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ForEach(model.steps) { step in
                Label {
                    Text(step.title).foregroundStyle(step.done ? .primary : .secondary)
                } icon: {
                    Image(systemName: step.done ? "checkmark.circle.fill" : "circle.dotted")
                        .foregroundStyle(step.done ? .green : .secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private var results: some View {
        let rows = model.categories.filter { $0.bytes > 0 }
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.totalBytes.formatted(.byteCount(style: .file)))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("can be cleaned.")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("\(model.selectedBytes.formatted(.byteCount(style: .file))) is selected.")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clean All Selected") {
                    model.beginClean()
                    onClean()
                }
                .buttonStyle(.glassProminent)
                .disabled(model.selectedBytes == 0 || model.isCleaning)
            }
            if rows.isEmpty {
                Label("Nothing to clean. This Mac is tidy.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            } else {
                Chart(rows) { category in
                    BarMark(
                        x: .value("Size", category.bytes),
                        y: .value("Category", category.title)
                    )
                    .foregroundStyle(CategoryStyle.of(category.id).color.gradient)
                    .cornerRadius(6)
                    .annotation(position: .trailing) {
                        Text(category.bytes.formatted(.byteCount(style: .file)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .chartXAxis(.hidden)
                .chartYSelection(value: $pickedTitle)
                .frame(height: CGFloat(rows.count) * 34 + 10)
                Text("Click a bar to open that category.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
}

/// Startup disk usage, like the Storage page in System Settings: used, can be cleaned, free.
struct DiskBar: View {
    let reclaimable: Int64

    var body: some View {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeLocalizedNameKey,
        ])
        let total = Int64(values?.volumeTotalCapacity ?? 0)
        let free = values?.volumeAvailableCapacityForImportantUsage ?? 0
        let used = max(0, total - free)
        let junk = min(reclaimable, used)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(values?.volumeLocalizedName ?? "Macintosh HD", systemImage: "internaldrive")
                    .font(.headline)
                Spacer()
                Text(
                    "\(free.formatted(.byteCount(style: .file))) available of \(total.formatted(.byteCount(style: .file)))"
                )
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    Rectangle().fill(Color.gray.opacity(0.6))
                        .frame(width: Self.share(used - junk, of: total) * geometry.size.width)
                    Rectangle().fill(Color.orange)
                        .frame(width: Self.share(junk, of: total) * geometry.size.width)
                    Rectangle().fill(Color.secondary.opacity(0.2))
                }
                .clipShape(Capsule())
            }
            .frame(height: 14)
            HStack(spacing: 14) {
                legend("Used", Color.gray.opacity(0.6))
                legend("Can be cleaned", .orange)
                legend("Free", Color.secondary.opacity(0.2))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title)
        }
    }

    static func share(_ part: Int64, of total: Int64) -> CGFloat {
        total > 0 ? CGFloat(Double(max(0, part)) / Double(total)) : 0
    }
}
