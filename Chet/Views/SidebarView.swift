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
                        ActivitySpinner(controlSize: .mini)
                        Text("Scanning").foregroundStyle(Theme.inkSecondary)
                    }
                    .selectionDisabled()
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
            Section("Configure") {
                row("tweaks", "Tweaks", symbol: "slider.horizontal.3")
            }
            Section("Tools") {
                row("applications", "Apps", symbol: "app.dashed")
                row("disk-map", "Storage", symbol: "internaldrive")
                row("homebrew", "Homebrew", symbol: "shippingbox")
            }
        }
        .listStyle(.sidebar)
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
        // The row exists once the step found something, but the step can still be adding to it.
        let working = model.isScanning && !(model.steps.first(where: { $0.id == step })?.done ?? false)
        return row(
            category.id, CategoryCopy.title(category.id, fallback: category.title),
            trailing: category.id == "snapshots"
                ? "\(model.snapshots.count)" : category.bytes.formatted(.byteCount(style: .file)),
            locked: category.needsFullDiskAccess,
            working: working)
    }

    private func row(
        _ id: String, _ title: String, trailing: String? = nil, locked: Bool = false,
        working: Bool = false, symbol: String? = nil
    ) -> some View {
        let glyph = symbol ?? CategoryStyle.of(id).symbol
        let isSelected = selection == id
        return Label {
            HStack(spacing: Spacing.s2) {
                Text(title)
                    .font(Typography.sidebar)
                    .lineLimit(1)
                    .modifier(
                        SidebarInk(isSelected: isSelected, tone: Theme.ink))
                if locked {
                    Image(systemName: "lock.fill")
                        .font(Typography.caption)
                        .modifier(SidebarInk(isSelected: isSelected, tone: Theme.inkSecondary))
                        .help("Some folders need Full Disk Access")
                        .accessibilityHidden(true)
                }
                Spacer(minLength: Spacing.s2)
                if working {
                    ActivitySpinner(controlSize: .mini)
                }
                if let trailing {
                    Text(trailing)
                        .font(Typography.caption)
                        .modifier(SidebarInk(isSelected: isSelected, tone: Theme.inkSecondary))
                        .monospacedDigit()
                }
            }
        } icon: {
            Image(systemName: glyph)
                .font(Typography.iconSidebar)
                .modifier(SidebarInk(isSelected: isSelected, tone: Theme.inkSecondary))
                .frame(width: 18)
        }
        .tag(id)
        .accessibilityIdentifier("sidebar.\(id)")
    }
}

/// The sidebar is system chrome, so the selected row draws its own label color. An explicit
/// color would override the system selection treatment, so it is used on unselected rows only.
private struct SidebarInk: ViewModifier {
    let isSelected: Bool
    let tone: Color

    func body(content: Content) -> some View {
        if isSelected {
            content
        } else {
            content.foregroundStyle(tone)
        }
    }
}
