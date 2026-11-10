import AppKit
import ChetCore
import SwiftUI

// MARK: - Tokens

/// Mode copy. One sentence, read by the page frame, so no screen writes its own variant.
enum PreviewCopy {
    static let statement = "Preview only. Nothing is changed."
    static let removals = "Preview only. Nothing will be removed."
    static let moves = "Preview only. Nothing will be moved."
    static let installs = "Preview only. Nothing will be installed."
    static let tweaks = TweakError.gatedCopy
}

enum Typography {
    static let display = Font.system(size: 34, weight: .semibold)
    static let title = Font.system(size: 24, weight: .semibold)
    static let section = Font.system(size: 16, weight: .semibold)
    static let body = Font.system(size: 15, weight: .regular)
    static let row = Font.system(size: 14, weight: .regular)
    static let sidebar = Font.system(size: 13, weight: .regular)
    static let caption = Font.system(size: 12, weight: .regular)
    static let metric = Font.system(size: 18, weight: .medium)

    // Glyph sizes come from the icon-size table in tokens.md. A view uses one of these,
    // never a literal `.font(.system(size:))`.
    static let iconAction = Font.system(size: 16, weight: .regular)
    static let iconSidebar = Font.system(size: 16, weight: .regular)
    static let iconRow = Font.system(size: 22, weight: .regular)
}

enum Spacing {
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s6: CGFloat = 24
    static let s8: CGFloat = 32
    static let s12: CGFloat = 48
}

enum Metrics {
    static let pageMargin: CGFloat = 24
    static let widePageMargin: CGFloat = 32
    static let gridCellMinWidth: CGFloat = 164
    static let rowHeight: CGFloat = 40
    static let commandBarMinHeight: CGFloat = 56
    static let tableHeaderHeight: CGFloat = 32
    /// Controls use one radius and one height so every primary action matches.
    static let controlRadius: CGFloat = 6
    static let panelRadius: CGFloat = 8
    static let controlMinWidth: CGFloat = 96
    static let statusStripHeight: CGFloat = 48
    static let capacityBarHeight: CGFloat = 10
    static let iconGutter: CGFloat = 22
    static let controlColumn: CGFloat = 150
    static let sheetWidth: CGFloat = 520
    static let detailSheetWidth: CGFloat = 540
    static let byteColumnWidth: CGFloat = 88
    static let chevronIconSize: CGFloat = 8
    static let compactRowHeight: CGFloat = 28
}

// MARK: - Primitives

struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 1)
    }
}

enum StatusTone {
    case neutral, amber, red, accent

    var color: Color {
        switch self {
        case .neutral: Theme.inkSecondary
        case .amber: Theme.amber
        case .red: Theme.red
        case .accent: Theme.accent
        }
    }
}

struct StatusLabel: View {
    let text: String
    let systemImage: String
    var tone: StatusTone = .neutral
    var help: String?

    var body: some View {
        HStack(spacing: Spacing.s1) {
            Image(systemName: systemImage)
                .font(Typography.iconAction)
            Text(text)
                .font(Typography.caption)
        }
        .foregroundStyle(tone.color)
        .help(help ?? text)
        .accessibilityElement(children: .combine)
    }
}

/// The one dry-run gate treatment. The call site supplies the verb that matches its action.
enum NoticeTone {
    case destructive, inert

    var systemImage: String {
        switch self {
        case .destructive: "exclamationmark.triangle"
        case .inert: "eye.slash"
        }
    }

    var tone: StatusTone {
        switch self {
        case .destructive: .amber
        case .inert: .neutral
        }
    }
}

struct PreviewNotice: View {
    let text: String
    var tone: NoticeTone = .destructive

    var body: some View {
        StatusLabel(
            text: text,
            systemImage: tone.systemImage,
            tone: tone.tone)
    }
}

/// A sortable column label. The arrow is reserved for the active column, and the whole label
/// shares one focus ring and hit area across every table.
struct SortColumnButton: View {
    let title: String
    let isActive: Bool
    let ascending: Bool
    var identifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Text(title)
                    .font(Typography.caption)
                Image(systemName: ascending ? "chevron.up" : "chevron.down")
                    .font(.system(size: Metrics.chevronIconSize, weight: .semibold))
                    .opacity(isActive ? 1 : 0)
            }
            .foregroundStyle(isActive ? Theme.ink : Theme.inkSecondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focusRing()
        .help("Sort by \(title)")
        .accessibilityLabel(title)
        .modifier(OptionalAccessibilityIdentifier(identifier: identifier))
    }
}

struct OptionalAccessibilityIdentifier: ViewModifier {
    let identifier: String?

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}

/// In-flow chrome bar on the system glass material. The glass sits inside the page margin so
/// content scrolls under it and the bar never floats.
struct GlassBar<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        GlassEffectContainer(spacing: Spacing.s2) {
            content()
                .padding(.horizontal, Spacing.s3)
                .padding(.vertical, Spacing.s2)
                .glassEffect(.regular, in: .rect(cornerRadius: Metrics.panelRadius))
        }
        .pageHorizontalPadding()
    }
}

/// One-line status bar: a labeled state, an optional action, an optional dismiss, on the
/// raised surface with a rule below. The inset, height, and surface are fixed here, so the
/// settings preview note and the top status strip cannot drift apart.
struct StatusStrip: View {
    struct Action {
        let title: String
        var accessibilityLabel: String? = nil
        let perform: () -> Void
    }

    struct Dismiss {
        let label: String
        let perform: () -> Void
    }

    let text: String
    let systemImage: String
    var tone: StatusTone = .neutral
    var action: Action? = nil
    var dismiss: Dismiss? = nil

    var body: some View {
        HStack(spacing: Spacing.s3) {
            StatusLabel(text: text, systemImage: systemImage, tone: tone)
            Spacer(minLength: Spacing.s3)
            if let action {
                SecondaryActionButton(
                    title: action.title,
                    accessibilityLabel: action.accessibilityLabel,
                    action: action.perform)
            }
            if let dismiss {
                IconActionButton(systemImage: "xmark", label: dismiss.label, action: dismiss.perform)
            }
        }
        .pageHorizontalPadding()
        .padding(.vertical, Spacing.s3)
        .frame(minHeight: Metrics.statusStripHeight)
        .glassEffect(.regular, in: .rect(cornerRadius: 0))
    }
}

struct PageHeader: View {
    let title: String
    var subtitle: String?
    var metric: String?
    var metricLabel: String?
    var icon: NSImage?

    var body: some View {
        VStack(spacing: Spacing.s3) {
            HStack(alignment: .top, spacing: Spacing.s3) {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 44, height: 44)
                }
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text(title)
                        .font(Typography.title)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(Typography.body)
                            .foregroundStyle(Theme.inkSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: Spacing.s3)
                // Always laid out, even without a number: a header that grows when a scan
                // finishes moves every row below it, and the eye has to find the page again.
                VStack(alignment: .trailing, spacing: 2) {
                    Text(metric ?? " ")
                        .font(Typography.display)
                        .monospacedDigit()
                        .foregroundStyle(metric == nil ? .clear : Theme.ink)
                        .lineLimit(1)
                    Text(metricLabel ?? " ")
                        .font(Typography.caption)
                        .foregroundStyle(metric == nil ? .clear : Theme.inkSecondary)
                        .lineLimit(1)
                }
                .accessibilityHidden(metric == nil)
            }
            Hairline()
        }
    }
}

/// One page frame for every destination. It owns the margin, the header position, the
/// measure, the gap under the header, and the bottom inset; a screen supplies its slots
/// and nothing else. Two screens therefore cannot drift apart, and a new screen cannot
/// invent its own chrome.
///
/// The header is laid out at its natural height and never compressed, so an oversized
/// body shrinks or clips instead of pushing the title under the titlebar.
struct PageScreen<Header: View, SubHeader: View, Content: View, Bar: View>: View {
    var scrolls: Bool
    let header: Header
    let subHeader: SubHeader
    let content: Content
    let bar: Bar

    init(
        scrolls: Bool = true,
        @ViewBuilder header: () -> Header,
        @ViewBuilder subHeader: () -> SubHeader,
        @ViewBuilder content: () -> Content,
        @ViewBuilder bar: () -> Bar
    ) {
        self.scrolls = scrolls
        self.header = header()
        self.subHeader = subHeader()
        self.content = content()
        self.bar = bar()
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Spacing.s3) {
                header
                    .pageHorizontalPadding()
                // A sub-header lays out full width: its own rows (breadcrumb, metrics)
                // carry the page margin so they can also draw dividers edge to edge.
                subHeader
            }
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
            .padding(.top, Spacing.s6)
            .padding(.bottom, Spacing.s3)

            if scrolls {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.s6) {
                        content
                    }
                    .pageHorizontalPadding()
                    .padding(.bottom, Spacing.s6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                // The builder result is a group of views, not a stack. Without the VStack
                // they lay out against each other and leave the page half empty.
                VStack(spacing: 0) {
                    content
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
            }

            // The frame states the app's mode once, for every destination. No screen repeats
            // it, and no screen has to make room for a strip that pushes the page down.
            if DryRun.enabled {
                Text(PreviewCopy.statement)
                    .font(Typography.caption)
                    .foregroundStyle(Theme.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .pageHorizontalPadding()
                    .padding(.top, Spacing.s1)
            }

            // A page without commands keeps the same usable height as one with them.
            if Bar.self == EmptyView.self {
                Color.clear.frame(height: Metrics.commandBarMinHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.paper)
        .backgroundExtensionEffect()
        .safeAreaBar(edge: .bottom) { bar }
    }
}

extension PageScreen where SubHeader == EmptyView, Bar == EmptyView {
    init(
        scrolls: Bool = true,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            scrolls: scrolls, header: header, subHeader: { EmptyView() },
            content: content, bar: { EmptyView() })
    }
}

extension PageScreen where SubHeader == EmptyView {
    init(
        scrolls: Bool = true,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content,
        @ViewBuilder bar: () -> Bar
    ) {
        self.init(
            scrolls: scrolls, header: header, subHeader: { EmptyView() },
            content: content, bar: bar)
    }
}

extension PageScreen where Bar == EmptyView {
    init(
        scrolls: Bool = true,
        @ViewBuilder header: () -> Header,
        @ViewBuilder subHeader: () -> SubHeader,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            scrolls: scrolls, header: header, subHeader: subHeader,
            content: content, bar: { EmptyView() })
    }
}

/// Shortcut that only applies when one is given, so call sites stay flat.
private struct ActionShortcut: ViewModifier {
    let key: KeyEquivalent?
    let modifiers: EventModifiers

    func body(content: Content) -> some View {
        if let key {
            content.keyboardShortcut(key, modifiers: modifiers)
        } else {
            content
        }
    }
}

/// Filled accent action. One per screen.
struct PrimaryActionButton: View {
    let title: String
    var systemImage: String?
    var isEnabled = true
    var help: String?
    var accessibilityLabel: String?
    var shortcut: KeyEquivalent?
    var shortcutModifiers: EventModifiers = []
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if let systemImage {
                Label(title, systemImage: systemImage).labelStyle(.titleAndIcon)
            } else {
                Text(title)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(Theme.accent)
        .frame(minWidth: Metrics.controlMinWidth)
        .disabled(!isEnabled)
        .help(help ?? title)
        .accessibilityLabel(accessibilityLabel ?? title)
        .modifier(ActionShortcut(key: shortcut, modifiers: shortcutModifiers))
    }
}

/// Filled red action. Permanent removal only.
struct DestructiveActionButton: View {
    let title: String
    var systemImage: String?
    var isEnabled = true
    var help: String?
    var accessibilityLabel: String?
    var shortcut: KeyEquivalent?
    var shortcutModifiers: EventModifiers = []
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if let systemImage {
                Label(title, systemImage: systemImage).labelStyle(.titleAndIcon)
            } else {
                Text(title)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .tint(Theme.red)
        .frame(minWidth: Metrics.controlMinWidth)
        .disabled(!isEnabled)
        .help(help ?? title)
        .accessibilityLabel(accessibilityLabel ?? title)
        .modifier(ActionShortcut(key: shortcut, modifiers: shortcutModifiers))
    }
}

/// Bordered action: cancel, pause, deselect, open elsewhere.
struct SecondaryActionButton: View {
    let title: String
    var systemImage: String?
    var isEnabled = true
    var help: String?
    var accessibilityLabel: String?
    var shortcut: KeyEquivalent?
    var shortcutModifiers: EventModifiers = []
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if let systemImage {
                Label(title, systemImage: systemImage).labelStyle(.titleAndIcon)
            } else {
                Text(title)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .disabled(!isEnabled)
        .help(help ?? title)
        .accessibilityLabel(accessibilityLabel ?? title)
        .modifier(ActionShortcut(key: shortcut, modifiers: shortcutModifiers))
    }
}

/// Text action inside a row or a list header: sort order, choose all copies.
struct QuietActionButton: View {
    let title: String
    var font: Font = Typography.caption
    var isEnabled = true
    var help: String?
    var accessibilityLabel: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(font)
                .foregroundStyle(isEnabled ? Theme.accent : Theme.inkTertiary)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .focusable()
        .focusRing()
        .disabled(!isEnabled)
        .help(help ?? title)
        .accessibilityLabel(accessibilityLabel ?? title)
    }
}

/// Glyph-only action. The label is required because there is no visible text.
struct IconActionButton: View {
    let systemImage: String
    let label: String
    var isEnabled = true
    var help: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(Typography.iconAction)
                .foregroundStyle(isEnabled ? Theme.inkSecondary : Theme.inkTertiary)
        }
        .buttonStyle(.plain)
        .frame(width: 40, height: 40)
        .contentShape(Rectangle())
        .focusable()
        .focusRing()
        .disabled(!isEnabled)
        .help(help ?? label)
        .accessibilityLabel(label)
    }
}

/// A clickable row, tile, glyph, or crumb: no fill, one focus ring, one hit shape, and the
/// help and accessibility wiring every one of them needs.
///
/// These were five hand-written buttons. Two had already drifted: the app tile had no
/// focus ring, and only some of them set an accessibility label. The label content stays
/// at the call site; the behaviour does not.
struct RowActionButton<Label: View>: View {
    let help: String
    var accessibilityLabel: String?
    var identifier: String?
    let action: () -> Void
    let label: Label

    init(
        help: String,
        accessibilityLabel: String? = nil,
        identifier: String? = nil,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.help = help
        self.accessibilityLabel = accessibilityLabel
        self.identifier = identifier
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            label.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focusRing()
        .help(help)
        .accessibilityLabel(accessibilityLabel ?? help)
        .modifier(OptionalAccessibilityIdentifier(identifier: identifier))
    }
}

/// One row of a table: the height, the inset, the selection wash, the pointer shape, and
/// the open gesture. Four tables and the storage ledger wrote this by hand, and their
/// insets had already drifted apart.
struct TableRow<Content: View>: View {
    var isHighlighted = false
    var inset: RowInset = .page
    var onOpen: (() -> Void)?
    let content: Content

    init(
        isHighlighted: Bool = false,
        inset: RowInset = .page,
        onOpen: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.isHighlighted = isHighlighted
        self.inset = inset
        self.onOpen = onOpen
        self.content = content()
    }

    var body: some View {
        let shell =
            content
            .frame(minHeight: Metrics.rowHeight)
            .modifier(TableRowInset(inset: inset))
            .background(isHighlighted ? Theme.accentSoft : Color.clear)
            .contentShape(Rectangle())

        if let onOpen {
            shell
                .focusable()
                .onKeyPress(.return) {
                    onOpen()
                    return .handled
                }
                .focusRing()
                .onTapGesture(count: 2) { onOpen() }
        } else {
            shell
        }
    }
}

/// Where a row sits: a page table runs to the page margin, a panel table to its own inset.
enum RowInset {
    case page
    case panel
}

private struct TableRowInset: ViewModifier {
    let inset: RowInset

    func body(content: Content) -> some View {
        switch inset {
        case .page: content.pageHorizontalPadding()
        case .panel: content.padding(.horizontal, Spacing.s3)
        }
    }
}

/// The remove checkbox a table row starts with: one label, one width, one disabled rule,
/// and an optional identifier so the selector map keeps working.
struct RowCheckbox: View {
    @Binding var isOn: Bool
    let label: String
    var width: CGFloat?
    var isEnabled = true
    var help: String?
    var identifier: String?

    init(
        isOn: Binding<Bool>, label: String, width: CGFloat? = nil,
        isEnabled: Bool = true, help: String? = nil, identifier: String? = nil
    ) {
        _isOn = isOn
        self.label = label
        self.width = width
        self.isEnabled = isEnabled
        self.help = help
        self.identifier = identifier
    }

    init(
        identifier: String, isOn: Binding<Bool>, label: String,
        width: CGFloat? = nil, isEnabled: Bool = true, help: String? = nil
    ) {
        self.init(
            isOn: isOn, label: label, width: width,
            isEnabled: isEnabled, help: help, identifier: identifier)
    }

    var body: some View {
        Toggle("", isOn: $isOn)
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(!isEnabled)
            .help(help ?? label)
            .accessibilityLabel(label)
            .modifier(OptionalAccessibilityIdentifier(identifier: identifier))
            .frame(width: width)
    }
}

/// A size column: monospaced and right aligned, so the numbers line up from row to row and
/// from table to table.
struct SizeColumn: View {
    let bytes: Int64
    var width: CGFloat?
    var foreground: Color = Theme.ink

    var body: some View {
        Text(bytes.formatted(.byteCount(style: .file)))
            .font(Typography.row)
            .monospacedDigit()
            .foregroundStyle(foreground)
            .lineLimit(1)
            .frame(width: width, alignment: .trailing)
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        VStack(spacing: Spacing.s2) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
                Text(title)
                    .font(Typography.section)
                    .foregroundStyle(Theme.ink)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(Typography.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .monospacedDigit()
                }
            }
            Hairline()
        }
    }
}

// MARK: - Selection and action

// MARK: - States

struct EmptyStateView: View {
    let title: String
    let message: String
    var actionIsPrimary = true
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Spacing.s3) {
            Text(title)
                .font(Typography.section)
                .foregroundStyle(Theme.ink)
            Text(message)
                .font(Typography.body)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                if actionIsPrimary {
                    PrimaryActionButton(title: actionTitle, action: action)
                } else {
                    SecondaryActionButton(title: actionTitle, action: action)
                }
            }
        }
        .multilineTextAlignment(.center)
        // A floor on the width: the window probes the minimum size with a near-zero width,
        // and the wrapped message then asks for hundreds of points of height.
        .frame(minWidth: 240, maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

/// An indeterminate spinner, drawn as a circle. A bare `ProgressView` becomes a
/// horizontal bar inside a toolbar, so the circular style is pinned here once.
struct ActivitySpinner: View {
    var controlSize: ControlSize = .small

    var body: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .controlSize(controlSize)
            .accessibilityHidden(true)
    }
}

struct LoadingStateView: View {
    let message: String

    var body: some View {
        HStack(spacing: Spacing.s2) {
            ActivitySpinner()
            Text(message)
                .font(Typography.body)
                .foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.s4)
    }
}

/// One scrolling table: a pinned column header over the rows. The header lives inside the
/// scroll view, so the first row sits directly under it instead of a dead band, and the header
/// stays visible while the list scrolls. The header and each row own their horizontal margin,
/// which keeps a column label over its cells.
enum ColumnRole {
    case mark, icon, name, location, version, size, status, age, local, kind, modified, risk
}

struct ColumnSpec {
    let width: CGFloat
    let alignment: HorizontalAlignment
}

enum ColumnRegistry {
    static let spacing = Spacing.s3
    static let headerHeight = Metrics.tableHeaderHeight

    static func spec(_ role: ColumnRole) -> ColumnSpec {
        switch role {
        case .mark: ColumnSpec(width: 20, alignment: .leading)
        case .icon: ColumnSpec(width: 22, alignment: .leading)
        case .name: ColumnSpec(width: 0, alignment: .leading)
        case .location: ColumnSpec(width: 140, alignment: .leading)
        case .version: ColumnSpec(width: 80, alignment: .leading)
        case .size: ColumnSpec(width: 90, alignment: .trailing)
        case .status: ColumnSpec(width: 118, alignment: .leading)
        case .age: ColumnSpec(width: 140, alignment: .trailing)
        case .local: ColumnSpec(width: 110, alignment: .leading)
        case .kind: ColumnSpec(width: 140, alignment: .leading)
        case .modified: ColumnSpec(width: 140, alignment: .leading)
        case .risk: ColumnSpec(width: 110, alignment: .leading)
        }
    }
}

/// One scrolling table: a pinned column header over the rows. The header lives inside the
/// scroll view, so the first row sits directly under it instead of a dead band, and the header
/// stays visible while the list scrolls. The header and each row own their horizontal margin,
/// which keeps a column label over its cells.
struct ColumnTable<Item: Identifiable, Header: View, Row: View>: View {
    let items: [Item]
    @ViewBuilder let header: Header
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(items) { item in
                        row(item)
                        if item.id != items.last?.id {
                            Hairline().pageHorizontalPadding()
                        }
                    }
                } header: {
                    header
                        .frame(height: ColumnRegistry.headerHeight)
                        .background(Theme.paperRaised)
                }
            }
        }
        .background(Theme.paper)
    }
}

/// The one ledger recipe: a raised, radius-6 box that scrolls and caps its height. A ledger
/// row takes `Metrics.byteColumnWidth` so every sheet measures the same width.
struct SheetLedgerBox<Content: View>: View {
    var maxHeight: CGFloat? = 220
    @ViewBuilder var content: () -> Content

    var body: some View {
        Group {
            if let maxHeight {
                ScrollView {
                    content()
                }
                .frame(maxHeight: maxHeight)
            } else {
                content()
            }
        }
        .padding(.horizontal, Spacing.s3)
        .background(Theme.paperRaised, in: .rect(corners: .fixed(Metrics.controlRadius)))
    }
}

/// The geometry every action sheet shares: 520 pt wide by default; detail sheets pass 540.
/// 24 pt padding, and an optional fixed height. The system supplies the sheet window; the
/// frame supplies the paper body.
struct SheetFrame<Content: View>: View {
    var width: CGFloat = Metrics.sheetWidth
    var height: CGFloat?
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(Spacing.s6)
            .frame(width: width, height: height)
            .background(Theme.paper)
    }
}

struct ErrorStateView: View {
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            StatusLabel(text: title, systemImage: "exclamationmark.triangle", tone: .amber)
            Text(message)
                .font(Typography.body)
                .foregroundStyle(Theme.inkSecondary)
            if let actionTitle, let action {
                SecondaryActionButton(title: actionTitle, action: action)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.s4)
    }
}

// MARK: - Capacity

enum CapacityLegendStyle {
    case full, reclaimable, none
}

struct CapacityBarView: View {
    let volumeName: String
    let total: Int64
    let free: Int64
    let reclaimable: Int64
    var showsHeader = true
    var legendStyle: CapacityLegendStyle = .full
    var height: CGFloat = Metrics.capacityBarHeight

    var body: some View {
        let used = max(0, total - free)
        let junk = min(max(0, reclaimable), used)
        VStack(alignment: .leading, spacing: Spacing.s2) {
            if showsHeader {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
                    Text(volumeName)
                        .font(Typography.section)
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    if total > 0 {
                        Text(
                            "\(free.formatted(.byteCount(style: .file))) available of \(total.formatted(.byteCount(style: .file)))"
                        )
                        .font(Typography.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.inkSecondary)
                    } else {
                        Text("Capacity unavailable")
                            .font(Typography.caption)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
            }
            if total > 0 {
                GeometryReader { geo in
                    HStack(spacing: 1) {
                        Rectangle()
                            .fill(Theme.capacityUsed)
                            .frame(width: share(used - junk) * geo.size.width)
                        Rectangle()
                            .fill(Theme.accent)
                            .frame(width: share(junk) * geo.size.width)
                        Rectangle()
                            .fill(Theme.capacityFree)
                    }
                }
                .frame(height: height)
                .overlay {
                    Rectangle().strokeBorder(Theme.hairline, lineWidth: 1)
                }
                switch legendStyle {
                case .full:
                    HStack(spacing: Spacing.s4) {
                        legend("Used", Theme.capacityUsed, used)
                        if reclaimable > 0 {
                            legend("Can be reclaimed", Theme.accent, reclaimable)
                        }
                        legend("Free", Theme.capacityFree, free)
                    }
                    .font(Typography.caption)
                    .foregroundStyle(Theme.inkSecondary)
                case .reclaimable:
                    if reclaimable > 0 {
                        legend("Can be reclaimed", Theme.accent, reclaimable)
                            .font(Typography.caption)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                case .none:
                    EmptyView()
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(volumeName). Used \(used.formatted(.byteCount(style: .file))), can be reclaimed \(reclaimable.formatted(.byteCount(style: .file))), free \(free.formatted(.byteCount(style: .file)))"
        )
    }

    private func legend(_ title: String, _ color: Color, _ value: Int64) -> some View {
        HStack(spacing: Spacing.s1) {
            Rectangle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text("\(title) \(value.formatted(.byteCount(style: .file)))")
                .monospacedDigit()
        }
    }

    private func share(_ part: Int64) -> CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(Double(max(0, part)) / Double(total))
    }
}

// MARK: - Focus

struct FocusRing: ViewModifier {
    @Environment(\.isFocused) private var isFocused

    func body(content: Content) -> some View {
        content.overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                    .strokeBorder(Theme.accent, lineWidth: 2)
            }
        }
    }
}

// MARK: - Page margin

private struct PageMarginKey: EnvironmentKey {
    static let defaultValue = Metrics.pageMargin
}

extension EnvironmentValues {
    var pageMargin: CGFloat {
        get { self[PageMarginKey.self] }
        set { self[PageMarginKey.self] = newValue }
    }
}

struct PageHorizontalPadding: ViewModifier {
    @Environment(\.pageMargin) private var margin

    func body(content: Content) -> some View {
        content.padding(.horizontal, margin)
    }
}

// MARK: - Helpers

extension View {
    func pageSurface() -> some View {
        background(Theme.paper)
    }

    func pageHorizontalPadding() -> some View {
        modifier(PageHorizontalPadding())
    }

    func focusRing() -> some View {
        modifier(FocusRing())
    }
}
