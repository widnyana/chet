import MackitCore
import SwiftUI

/// The clean-mode spine: overview, reclaimable categories, and the tools.
/// Applications is a destination, not a card on the overview.
struct SidebarView: View {
    @Environment(ScanModel.self) private var model
    @Binding var selection: String?

    var body: some View {
        List(selection: $selection) {
            row("overview", "Overview", running: model.isScanning)
            if !model.categories.isEmpty || model.isScanning {
                Section("Reclaimable") {
                    if model.categories.isEmpty {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("Scanning").foregroundStyle(Theme.inkSecondary)
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
            Section("Tools") {
                row("applications", "Applications", symbol: "app.fill", emphasis: true)
                row("disk-map", "Disk map", symbol: "square.grid.3x3.fill", emphasis: true)
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 250)
    }

    private func row(
        _ id: String, _ title: String, trailing: String? = nil, locked: Bool = false,
        running: Bool = false, dimmed: Bool = false, symbol: String? = nil, emphasis: Bool = false
    ) -> some View {
        let glyph = symbol ?? CategoryStyle.of(id).symbol
        return Label {
            HStack(spacing: Spacing.s2) {
                Text(title)
                    .lineLimit(1)
                    .foregroundStyle(dimmed ? AnyShapeStyle(Theme.inkTertiary) : AnyShapeStyle(Theme.ink))
                if running {
                    ProgressView().controlSize(.mini)
                }
                if locked {
                    Image(systemName: "lock.fill")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .help("Some folders need Full Disk Access")
                }
                Spacer(minLength: Spacing.s2)
                if let trailing {
                    Text(trailing)
                        .font(Typography.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .monospacedDigit()
                }
            }
        } icon: {
            Image(systemName: glyph)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(emphasis ? Theme.ink : Theme.inkSecondary)
                .frame(width: 20)
        }
        .tag(id)
    }
}
