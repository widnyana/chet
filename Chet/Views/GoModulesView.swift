import AppKit
import ChetCore
import SwiftUI

struct GoModulesView: View {
    @Environment(GoModulesModel.self) private var model

    var body: some View {
        @Bindable var model = model
        PageScreen(
            scrolls: false,
            header: {
                PageHeader(title: "Go", subtitle: model.subtitle)
                    .accessibilityIdentifier("go.header")
            },
            content: { content },
            bar: { commandBar }
        )
        .onAppear { model.load() }
        .alert(
            "Go",
            isPresented: Binding(
                get: { model.message != nil },
                set: { if !$0 { model.message = nil } })
        ) {
            Button("OK", role: .cancel) { model.message = nil }
        } message: {
            Text(model.message ?? "")
        }
        .confirmationDialog(
            "Remove the Go module cache?",
            isPresented: $model.showConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) { model.remove() }
                .accessibilityIdentifier("go.confirm")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(removalMessage)
        }
    }

    @ViewBuilder private var content: some View {
        if model.isLoading && model.info == nil {
            LoadingStateView(message: "Measuring the module cache.")
                .pageHorizontalPadding()
        } else if !model.isAvailable {
            EmptyStateView(
                title: "Go is not installed",
                message: "Chet looked for Go in Homebrew, mise, gvm, and a native install.",
                actionTitle: "Open go.dev",
                action: { NSWorkspace.shared.open(URL(string: "https://go.dev/dl")!) }
            )
            .pageHorizontalPadding()
        } else if let info = model.info, info.bytes == 0 {
            EmptyStateView(
                title: "The module cache is empty",
                message: info.cachePath,
                actionTitle: "Reload",
                action: { model.reload() }
            )
            .pageHorizontalPadding()
        } else if let info = model.info {
            ledger(info)
        } else {
            LoadingStateView(message: "Measuring the module cache.")
                .pageHorizontalPadding()
        }
    }

    private func ledger(_ info: GoModules.Info) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Module cache")
            DefinitionRow(
                label: "Location", value: info.cachePath, identifier: "go.cache-path")
            Hairline()
            DefinitionRow(label: "Size", value: model.sizeText, identifier: "go.cache-size")
            Hairline()
            DefinitionRow(
                label: "Modules", value: "\(info.moduleCount)", identifier: "go.module-count")
            Hairline()
            DefinitionRow(
                label: "Toolchain", value: "\(info.source.rawValue) · \(info.executable)",
                identifier: "go.toolchain")
        }
        .pageHorizontalPadding()
    }

    private var commandBar: some View {
        CommandBar(
            metric: model.sizeText,
            detail: "Module cache",
            actionTitle: "Remove module cache…",
            actionSystemImage: "trash",
            isEnabled: model.canRemove,
            isDestructive: true,
            isWorking: model.isWorking,
            secondaryTitle: "Reload",
            secondaryAction: model.reload,
            help: "Remove the module cache with go clean -modcache",
            disabledReason: disabledReason,
            primaryIdentifier: "go.remove",
            secondaryIdentifier: "go.reload",
            action: { model.showConfirm = true })
    }

    private var disabledReason: String? {
        if !model.isAvailable { return "Go is not installed." }
        if let info = model.info, info.bytes == 0 { return "The module cache is empty." }
        return nil
    }

    private var removalMessage: String {
        let message =
            "This removes \(model.sizeText) from the module cache. The next build downloads them again."
        return DryRun.enabled ? PreviewCopy.removals + " " + message : message
    }
}
