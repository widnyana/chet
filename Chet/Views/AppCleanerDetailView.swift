import AppKit
import ChetCore
import SwiftUI

/// The review surface for one app: the app bundle, the files it leaves behind, and one
/// command bar. Reached by pushing from the app browser.
struct AppCleanerDetailView: View {
    @Environment(AppCleanerModel.self) private var model
    let app: InstalledApp

    var body: some View {
        @Bindable var model = model
        PageScreen(
            scrolls: false,
            header: {
                PageHeader(
                    title: app.name,
                    subtitle: subtitle,
                    metric: model.appBytes.formatted(.byteCount(style: .file)),
                    metricLabel: "app size",
                    icon: IconCache.icon(for: app.url)
                )
            },
            subHeader: { EmptyView() },
            content: {
                details
                if model.isRunning {
                    warningRow("Running. Quit it before removing.", icon: "bolt.fill", tone: .amber)
                }
                if !app.isWritable {
                    warningRow(
                        "Needs administrator. Chet cannot move this app.", icon: "lock.fill",
                        tone: .amber)
                }
                appBundleRow(selected: $model.appSelected)
                if model.isLoadingDetail {
                    LoadingStateView(message: "Looking for related files")
                        .pageHorizontalPadding()
                    Spacer()
                } else if model.components.isEmpty {
                    EmptyStateView(
                        title: "No related files",
                        message: "The app bundle can still be removed."
                    )
                    .pageHorizontalPadding()
                } else {
                    relatedFiles
                }
            },
            bar: { commandBar }
        )
        .sheet(
            isPresented: Binding(
                get: { model.showConfirm && model.selectedApp != nil },
                set: { model.showConfirm = $0 })
        ) {
            AppUninstallConfirmSheet()
        }
        .onAppear { model.refreshRunningState() }
        .onChange(of: model.showConfirm) { _, showing in
            if showing {
                VerboseLog.event(.debug, .ui, .uiSheetPresented, .code(.sheet, .sheetClean))
            }
        }
    }

    private var details: some View {
        HStack(spacing: Spacing.s3) {
            Text(app.url.path)
                .font(Typography.caption)
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: Spacing.s3)
            SecondaryActionButton(
                title: "Reveal in Finder",
                action: { NSWorkspace.shared.activateFileViewerSelecting([app.url]) })
        }
        .pageHorizontalPadding()
        .padding(.bottom, Spacing.s2)
    }

    private func warningRow(_ text: String, icon: String, tone: StatusTone) -> some View {
        VStack(spacing: 0) {
            HStack {
                StatusLabel(text: text, systemImage: icon, tone: tone)
                Spacer()
            }
            .pageHorizontalPadding()
            .padding(.vertical, Spacing.s2)
            Hairline()
        }
    }

    private var subtitle: String {
        let parts = [
            app.version.map { "Version \($0)" },
            app.bundleID,
        ].compactMap { $0 }
        return parts.isEmpty ? "Unknown" : parts.joined(separator: ", ")
    }

    private func appBundleRow(selected: Binding<Bool>) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.s3) {
                VStack(alignment: .leading, spacing: 1) {
                    Toggle("Remove app bundle", isOn: selected)
                        .toggleStyle(.checkbox)
                        .disabled(model.isRunning || !app.isWritable)
                        .accessibilityLabel("Remove \(app.name) app bundle")
                    if !selected.wrappedValue {
                        Text("The app stays installed.")
                            .font(Typography.caption)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                Spacer()
                Text(model.isLoadingDetail ? "Measuring" : model.appBytes.formatted(.byteCount(style: .file)))
                    .font(Typography.metric)
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
            }
            .pageHorizontalPadding()
            .padding(.vertical, Spacing.s2)
            .frame(minHeight: Metrics.rowHeight)
            Hairline()
        }
    }

    private var relatedFiles: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.s3) {
                Text("Related files")
                    .font(Typography.section)
                    .foregroundStyle(Theme.ink)
                Text("\(model.selectedComponentList.count) of \(model.components.count) selected")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .monospacedDigit()
                Spacer()
                Menu {
                    Button("Exact matches only", systemImage: "checkmark") { model.selectExact() }
                    Button("All selectable", systemImage: "checklist") { model.selectAllSelectable() }
                    Button("None", systemImage: "circle") { model.clearComponents() }
                } label: {
                    Label("Select", systemImage: "checklist")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .pageHorizontalPadding()
            .padding(.vertical, Spacing.s2)
            Hairline()
            List {
                ForEach(grouped, id: \.kind) { group in
                    Section {
                        ForEach(group.items) { component in
                            OwnershipRow(component: component)
                        }
                    } header: {
                        HStack {
                            Text(AppCopy.component(group.kind))
                            Spacer()
                            Text(group.items.reduce(0) { $0 + $1.bytes }.formatted(.byteCount(style: .file)))
                                .monospacedDigit()
                        }
                        .font(Typography.caption)
                        .foregroundStyle(Theme.inkSecondary)
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .background(Theme.paper)
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

    private var commandBar: some View {
        CommandBar(
            metric: model.selectedBytes.formatted(.byteCount(style: .file)),
            detail: model.selectedCount == 1
                ? "1 item selected" : "\(model.selectedCount) items selected",
            actionTitle: "Move to Trash",
            isEnabled: model.canRemove,
            isWorking: model.isRemoving,
            help: "Review and move the selected items to the Trash",
            accessibilityLabel: "Move to Trash, \(model.selectedCount) items",
            disabledReason: "Select an item to remove.",
            action: { model.beginRemoval() })
    }
}

private struct OwnershipRow: View {
    @Environment(AppCleanerModel.self) private var model
    let component: AppComponent

    var body: some View {
        let selected = model.selectedComponents.contains(component.url)
        HStack(spacing: Spacing.s2) {
            RowCheckbox(
                identifier: "cleaner.select.\(RowIdentifier.path(component.url))",
                isOn: Binding(get: { selected }, set: { model.setComponent(component, $0) }),
                label: "Remove \(component.url.lastPathComponent)",
                isEnabled: model.canSelect(component))
            Image(nsImage: IconCache.icon(for: component.url))
                .resizable()
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(component.url.lastPathComponent)
                    .font(Typography.row)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                HStack(spacing: Spacing.s2) {
                    Text(DisplayName.location(of: component.url))
                        .font(Typography.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    ownershipLabel
                }
            }
            Spacer(minLength: Spacing.s2)
            SizeColumn(bytes: component.bytes, foreground: Theme.inkSecondary)
        }
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([component.url])
            }
        }
        .help(component.url.path)
    }

    private var ownershipLabel: some View {
        StatusLabel(
            text: AppCopy.ownership(component.ownership),
            systemImage: ownershipSymbol,
            tone: component.ownership == .privileged
                ? .amber : (component.ownership == .systemProtected ? .red : .neutral))
    }

    private var ownershipSymbol: String {
        switch component.ownership {
        case .exclusive: "checkmark"
        case .probable: "questionmark.circle"
        case .shared: "person.2"
        case .privileged: "lock.fill"
        case .systemProtected: "shield.lefthalf.filled"
        }
    }
}
