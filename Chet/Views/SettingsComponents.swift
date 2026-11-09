import AppKit
import ChetCore
import SwiftUI

// MARK: - Pane identity

/// One pane of the settings window. The title and symbol live here once, so the switcher,
/// the window, and any future menu entry cannot drift apart.
enum SettingsPane: String, CaseIterable, Identifiable {
    case whatToFind
    case limits
    case folders

    var id: String { rawValue }

    var title: String {
        switch self {
        case .whatToFind: "What to find"
        case .limits: "Limits"
        case .folders: "Folders"
        }
    }

    var systemImage: String {
        switch self {
        case .whatToFind: "magnifyingglass"
        case .limits: "ruler"
        case .folders: "folder"
        }
    }
}

// MARK: - Pane switcher

/// The pane switcher: one segment per pane, every segment the same width, icon over word.
/// A system `TabView` sizes its items to their own text, so the three headings came out at
/// three widths. This component gives each pane an equal share and keeps the selected state
/// in one place.
struct SettingsPaneSwitcher: View {
    @Binding var selection: SettingsPane

    var body: some View {
        HStack(spacing: Spacing.s1) {
            ForEach(SettingsPane.allCases) { pane in
                SettingsPaneSegment(
                    pane: pane,
                    isSelected: pane == selection,
                    action: { selection = pane })
            }
        }
        .padding(.horizontal, Metrics.pageMargin)
        .padding(.vertical, Spacing.s2)
        .background(Theme.paper)
    }
}

private struct SettingsPaneSegment: View {
    let pane: SettingsPane
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.s1) {
                Image(systemName: pane.systemImage)
                    .font(Typography.row)
                Text(pane.title)
                    .font(Typography.caption)
            }
            .foregroundStyle(isSelected ? Theme.accent : Theme.inkSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.s2)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                    .fill(isSelected ? Theme.accentSoft : Color.clear))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(pane.title)
        .accessibilityIdentifier("settings.pane.\(pane.rawValue)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Window chrome

/// SwiftUI's `Settings` scene puts the pane buttons in the window toolbar and repeats the
/// active pane name in the title bar. The toolbar already names the pane, so the title text
/// is hidden; the window keeps its title for accessibility and the Window menu.
struct SettingsWindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.titleVisibility = .hidden
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            view.window?.titleVisibility = .hidden
        }
    }
}

// MARK: - Pane container

/// The scroll container every pane shares: the one-line note about when changes apply, then
/// the panels, on the page margin. It fills the window width so every panel ends on the
/// same edge.
struct SettingsPaneView<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                Text("Changes apply to the next scan.")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.inkSecondary)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.s4)
        }
    }
}

// MARK: - Panel parts

/// A raised settings group: a small title over rows on `paperRaised`, one radius step up
/// from the page. Settings is the app's only raised surface; every other page stays flat.
struct SettingsPanel<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(Typography.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.inkSecondary)
                .padding(.horizontal, Spacing.s3)
                .padding(.top, Spacing.s3)
                .padding(.bottom, SettingsGrid.rowPadding)
            Grid(alignment: .leading, horizontalSpacing: Spacing.s3, verticalSpacing: 0) {
                content
            }
            .padding(.horizontal, Spacing.s3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, Spacing.s2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.paperRaised))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.hairline))
    }
}

/// The measurements every settings panel shares. The control column is sized by its widest
/// control through the panel's `Grid`, so a switch and a slider both sit on the trailing
/// edge and the label column keeps one width per panel.
enum SettingsGrid {
    static let row = Metrics.rowHeight
    static let rowPadding = Spacing.s2
    static let slider: CGFloat = 150
    static let valueColumn: CGFloat = 56
}

/// One setting: label and optional detail in the label column, the control in the shared
/// control column on the right.
struct SettingsRow<Control: View>: View {
    let label: String
    var detail: String?
    @ViewBuilder var control: Control

    var body: some View {
        GridRow {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(label)
                    .font(Typography.body)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let detail {
                    Text(detail)
                        .font(Typography.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, SettingsGrid.rowPadding)
            control
                .gridColumnAlignment(.trailing)
                .padding(.vertical, SettingsGrid.rowPadding)
        }
    }
}

/// The row used for a panel's own action, aligned to the same control column as a setting.
struct SettingsActionRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GridRow {
            Color.clear
                .frame(width: 0, height: 0)
            content
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.vertical, SettingsGrid.rowPadding)
        }
    }
}

struct SettingsNote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Typography.caption)
            .foregroundStyle(Theme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .gridCellColumns(2)
            .padding(.vertical, SettingsGrid.rowPadding)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Hairline()
            .gridCellColumns(2)
    }
}

// MARK: - Row controls

/// One switch setting. The row and the switch are built together so every switch in the
/// window gets the same size, alignment, and accessibility label as its row title.
struct SettingsToggleRow: View {
    let label: String
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(label: label, detail: detail) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel(label)
        }
    }
}

/// One slider setting. The track keeps a fixed width and the readout a fixed column, so the
/// numeric text does not shift the track as the value grows.
struct SettingsSliderRow: View {
    let label: String
    let readout: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        SettingsRow(label: label) {
            HStack(spacing: Spacing.s2) {
                Slider(value: $value, in: range, step: step)
                    .frame(width: SettingsGrid.slider)
                    .controlSize(.small)
                    .accessibilityLabel(label)
                    .accessibilityValue(readout)
                Text(readout)
                    .font(Typography.row)
                    .monospacedDigit()
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(width: SettingsGrid.valueColumn, alignment: .trailing)
            }
        }
    }
}
