import ChetCore
import SwiftUI

/// The clean-mode spine: Home, the categories split by what the user has to decide, and
/// the two tools. Apps is a destination, not a card on Home.
struct SidebarView: View {
    @Environment(ScanModel.self) private var model
    @Binding var selection: String?

    var body: some View {
        List(selection: $selection) {
            row("overview", "Home", symbol: "house")
            if model.isScanning && safeRows.isEmpty && reviewRows.isEmpty {
                Section {
                    HStack(spacing: Spacing.s2) {
                        ProgressView().controlSize(.mini)
                        Text("Scanning").foregroundStyle(Theme.inkSecondary)
                    }
                    .tag("scanning-placeholder")
                }
            }
            if !safeRows.isEmpty {
                Section("Safe to remove") {
                    ForEach(safeRows) { category in categoryRow(category) }
                }
            }
            if !reviewRows.isEmpty {
                Section("Check first") {
                    ForEach(reviewRows) { category in categoryRow(category) }
                }
            }
            Section("Tools") {
                row("applications", "Apps", symbol: "app.dashed", emphasis: true)
                row("disk-map", "Storage", symbol: "internaldrive", emphasis: true)
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 250)
    }

    /// Rows Home would show: something to remove, or snapshots that exist.
    private var visibleCategories: [CategoryState] {
        model.categories.filter { $0.bytes > 0 || ($0.id == "snapshots" && !model.snapshots.isEmpty) }
    }

    private var safeRows: [CategoryState] {
        visibleCategories.filter { CategoryCopy.section($0.id, risk: $0.items.first?.risk) == .safe }
    }

    private var reviewRows: [CategoryState] {
        visibleCategories.filter { CategoryCopy.section($0.id, risk: $0.items.first?.risk) == .review }
    }

    private func categoryRow(_ category: CategoryState) -> some View {
        let step = ScanStatusView.step(forCategory: category.id)
        let running = model.isScanning && model.currentStep == step
        let pending =
            model.isScanning && !(model.steps.first(where: { $0.id == step })?.done ?? false)
            && category.bytes == 0
        return row(
            category.id, CategoryCopy.title(category.id, fallback: category.title),
            trailing: category.id == "snapshots"
                ? "\(model.snapshots.count)" : category.bytes.formatted(.byteCount(style: .file)),
            locked: category.needsFullDiskAccess,
            running: running, dimmed: pending)
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
