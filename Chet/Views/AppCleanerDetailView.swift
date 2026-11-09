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
        VStack(spacing: 0) {
            PageHeader(
                title: app.name,
                subtitle: app.version.map { "Version \($0)" } ?? "Version unknown",
                metric: model.appBytes.formatted(.byteCount(style: .file)),
                metricLabel: "app size",
                icon: IconCache.icon(for: app.url)
            )
            .padding(.horizontal, Metrics.widePageMargin)
            .padding(.top, Spacing.s6)
            .padding(.bottom, Spacing.s2)
            details
            if model.isRunning {
                warningRow("This app is open. Quit it before removing.", icon: "bolt.fill", tone: .amber)
            }
            if !app.isWritable {
                warningRow(
                    "Chet needs an administrator to remove this app.", icon: "lock.fill", tone: .amber)
            }
            appBundleRow(selected: $model.appSelected)
            if model.isLoadingDetail {
                LoadingStateView(message: "Looking for files left by this app")
                    .padding(.horizontal, Metrics.widePageMargin)
                Spacer()
            } else if model.components.isEmpty {
                EmptyStateView(
                    title: "No files left behind",
                    message: "The app can still be removed.",
                    systemImage: "folder.badge.questionmark")
                .padding(.horizontal, Metrics.widePageMargin)
            } else {
                relatedFiles
            }
        }
        .background(Theme.paper)
        .safeAreaInset(edge: .bottom) { commandBar }
        .sheet(
            isPresented: Binding(
                get: { model.showConfirm && model.selectedApp != nil },
                set: { model.showConfirm = $0 })
        ) {
            AppUninstallConfirmSheet()
        }
        .onAppear { model.refreshRunningState() }
    }

    private var details: some View {
        DisclosureGroup("Details") {
            HStack(spacing: Spacing.s3) {
                Text(app.url.path)
                    .font(Typography.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: Spacing.s3)
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([app.url])
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.top, Spacing.s1)
        }
        .padding(.horizontal, Metrics.widePageMargin)
        .padding(.bottom, Spacing.s2)
    }

    private func warningRow(_ text: String, icon: String, tone: StatusTone) -> some View {
        VStack(spacing: 0) {
            HStack {
                StatusLabel(text: text, systemImage: icon, tone: tone)
                Spacer()
            }
            .padding(.horizontal, Metrics.widePageMargin)
            .padding(.vertical, Spacing.s2)
            Hairline()
        }
    }

    private func appBundleRow(selected: Binding<Bool>) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.s3) {
                VStack(alignment: .leading, spacing: 1) {
                    Toggle("Remove the app", isOn: selected)
                        .toggleStyle(.checkbox)
                        .disabled(model.isRunning || !app.isWritable)
                        .accessibilityLabel("Remove \(app.name)")
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
                    .foregroundStyle(Theme.inkSecondary)
            }
            .padding(.horizontal, Metrics.widePageMargin)
            .padding(.vertical, Spacing.s2)
            Hairline()
        }
    }

    private var relatedFiles: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.s3) {
                Text("Files left behind")
                    .font(Typography.section)
                    .foregroundStyle(Theme.ink)
                Text("\(model.selectedComponentList.count) of \(model.components.count) chosen")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .monospacedDigit()
                Spacer()
                Menu {
                    Button("Only exact matches", systemImage: "checkmark") { model.selectExact() }
                    Button("All removable", systemImage: "checklist") { model.selectAllSelectable() }
                    Button("None", systemImage: "circle") { model.clearComponents() }
                } label: {
                    Label("Choose", systemImage: "checklist")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, Metrics.widePageMargin)
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
            action: { model.beginRemoval() })
    }
}

private struct OwnershipRow: View {
    @Environment(AppCleanerModel.self) private var model
    let component: AppComponent

    var body: some View {
        let selected = model.selectedComponents.contains(component.url)
        HStack(spacing: Spacing.s2) {
            Toggle(
                "Remove", isOn: Binding(get: { selected }, set: { model.setComponent(component, $0) })
            )
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(!component.isSelectable)
            .accessibilityLabel("Remove \(component.url.lastPathComponent)")
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
            Text(component.bytes.formatted(.byteCount(style: .file)))
                .font(Typography.row)
                .monospacedDigit()
                .foregroundStyle(Theme.inkSecondary)
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
            tone: component.ownership == .privileged ? .amber : (component.ownership == .systemProtected ? .red : .neutral))
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
