import MackitCore
import SwiftUI

struct SidebarView: View {
    @Environment(ScanModel.self) private var model
    @Binding var selection: String?

    var body: some View {
        List(selection: $selection) {
            row("overview", "Overview")
            if !model.categories.isEmpty {
                Section("Reclaimable") {
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
        .navigationSplitViewColumnWidth(min: 240, ideal: 280)
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
