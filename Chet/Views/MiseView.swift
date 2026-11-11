import ChetCore
import SwiftUI

struct MiseView: View {
    @Environment(MiseModel.self) private var model

    var body: some View {
        PageScreen(
            scrolls: false,
            header: {
                PageHeader(
                    title: "mise",
                    subtitle:
                        "Tool versions declared in your mise config. Chet reads them; it does not change them."
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("mise")
                .accessibilityAddTraits(.isStaticText)
                .accessibilityIdentifier("mise.header")
            },
            subHeader: {
                toolbar
            },
            content: {
                content
            }
        )
        .task { model.load() }
        .onAppear {
            VerboseLog.event(.debug, .ui, .uiViewAppeared, .code(.view, .viewMise))
        }
    }

    private var toolbar: some View {
        HStack(spacing: Spacing.s3) {
            QuietActionButton(
                title: "Read again",
                help: "Read the config and the installed mise tools again"
            ) {
                model.reload()
            }
            .accessibilityLabel("Read again")
            .accessibilityIdentifier("mise.refresh")
            Text("\(model.snapshot?.tools.count ?? 0) tools")
                .font(Typography.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.inkSecondary)
                .accessibilityIdentifier("mise.page")
            Spacer()
        }
        .pageHorizontalPadding()
    }

    @ViewBuilder private var content: some View {
        if model.isLoading && model.snapshot == nil {
            LoadingStateView(message: "Reading your mise tools.")
                .pageHorizontalPadding()
        } else if let snapshot = model.snapshot {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                if let error = snapshot.error {
                    StatusLabel(
                        text: error,
                        systemImage: "exclamationmark.triangle",
                        tone: .amber
                    )
                    .pageHorizontalPadding()
                }
                if snapshot.tools.isEmpty {
                    EmptyStateView(
                        title: "No tools declared",
                        message: "The mise config has no tools table."
                    )
                    .accessibilityIdentifier("mise.empty")
                    .pageHorizontalPadding()
                } else {
                    table(snapshot.tools)
                }
                locations(snapshot)
            }
        }
    }

    private func table(_ tools: [Mise.Tool]) -> some View {
        ColumnTable(items: tools) {
            tableHeader
        } row: { tool in
            row(tool)
        }
    }

    private var tableHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: ColumnRegistry.spacing) {
                Text("Tool")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Requested")
                    .frame(width: ColumnRegistry.spec(.version).width, alignment: .leading)
                Text("Status")
                    .frame(width: ColumnRegistry.spec(.status).width, alignment: .leading)
            }
            .font(Typography.caption)
            .foregroundStyle(Theme.inkSecondary)
            .pageHorizontalPadding()
            .padding(.vertical, Spacing.s2)
            Hairline()
        }
    }

    private func row(_ tool: Mise.Tool) -> some View {
        TableRow {
            HStack(spacing: ColumnRegistry.spacing) {
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text(tool.name)
                        .font(Typography.row)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .accessibilityLabel(tool.name)
                        .accessibilityIdentifier(toolIdentifier(tool))
                    if let installPath = tool.installPath {
                        Text(installPath)
                            .font(Typography.caption)
                            .foregroundStyle(Theme.inkSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(tool.requested)
                    .font(Typography.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                    .frame(width: ColumnRegistry.spec(.version).width, alignment: .leading)
                status(tool)
                    .frame(width: ColumnRegistry.spec(.status).width, alignment: .leading)
            }
        }
    }

    @ViewBuilder private func status(_ tool: Mise.Tool) -> some View {
        if !tool.installed || tool.resolved == nil {
            StatusLabel(
                text: "Not installed",
                systemImage: "exclamationmark.triangle",
                tone: .amber)
        } else if tool.active {
            StatusLabel(text: "Active", systemImage: "checkmark.circle", tone: .accent)
        } else {
            StatusLabel(text: "Inactive", systemImage: "minus.circle", tone: .neutral)
        }
    }

    private func locations(_ snapshot: Mise.Snapshot) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            SectionHeader(title: "Locations")
                .pageHorizontalPadding()
            VStack(spacing: 0) {
                MiseLocationRow(
                    label: "Config",
                    path: snapshot.configPath,
                    identifier: "mise.config")
                Hairline()
                    .pageHorizontalPadding()
                MiseLocationRow(
                    label: "Cache",
                    path: snapshot.cachePath ?? "Unavailable",
                    identifier: "mise.cache")
            }
        }
    }

    private func toolIdentifier(_ tool: Mise.Tool) -> String {
        "mise.tool.\(Self.slug(tool.name)).\(Self.slug(tool.requested))"
    }

    private static func slug(_ value: String) -> String {
        String(
            value.lowercased().map { character in
                character.isASCII && (character.isLetter || character.isNumber)
                    ? character : Character(".")
            })
    }
}

private struct MiseLocationRow: View {
    let label: String
    let path: String
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(Theme.inkSecondary)
            Text(path)
                .font(Typography.caption)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(path)
                .accessibilityIdentifier(identifier)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pageHorizontalPadding()
        .padding(.vertical, Spacing.s1)
    }
}
