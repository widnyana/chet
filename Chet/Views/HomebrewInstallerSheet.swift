import ChetCore
import SwiftUI

/// The install sheet: search Homebrew's names, mark the ones to install, and add a tap. The sheet
/// reports tap and install failures in place, because a page alert cannot present over a sheet.
struct HomebrewInstallerSheet: View {
    @Environment(HomebrewModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model
        SheetFrame(height: 460) {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text("Install a package")
                        .font(Typography.title)
                        .foregroundStyle(Theme.ink)
                    Text("Search Homebrew's catalog, then mark the names to install.")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }

                HStack(spacing: Spacing.s2) {
                    TextField("Search formulae and casks", text: $model.searchText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { model.search() }
                        .accessibilityIdentifier("homebrew.search.field")
                    SecondaryActionButton(
                        title: "Search",
                        isEnabled: model.canSearch,
                        action: { model.search() })
                }

                results

                VStack(alignment: .leading, spacing: Spacing.s2) {
                    HStack(spacing: Spacing.s2) {
                        TextField("Add a tap, e.g. user/repo", text: $model.tapText)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { model.addTap() }
                            .accessibilityIdentifier("homebrew.tap.field")
                        SecondaryActionButton(
                            title: "Add tap",
                            isEnabled: model.canAddTap,
                            action: { model.addTap() })
                    }
                    if let status = model.installerStatus {
                        StatusLabel(
                            text: status,
                            systemImage: model.installerFailed
                                ? "exclamationmark.triangle" : "checkmark.circle",
                            tone: model.installerFailed ? .red : .neutral
                        )
                        .accessibilityIdentifier("homebrew.installer.status")
                    }
                }

                if DryRun.enabled {
                    StatusLabel(
                        text: "Preview only. Nothing will be installed.",
                        systemImage: "exclamationmark.triangle",
                        tone: .amber)
                }

                HStack {
                    Spacer()
                    SecondaryActionButton(title: "Cancel", shortcut: .escape, action: { dismiss() })
                    PrimaryActionButton(
                        title: "Install",
                        isEnabled: model.canInstall,
                        shortcut: .return,
                        action: { model.install() })
                }
            }
        }
    }

    @ViewBuilder private var results: some View {
        if model.isSearching {
            LoadingStateView(message: "Searching Homebrew")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else if let message = model.searchMessage {
            ErrorStateView(
                title: "Could not search Homebrew",
                message: "brew did not answer. Check the connection, then try again.",
                actionTitle: "Try again",
                action: { model.search() }
            )
            .help(message)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else if !model.hasSearched {
            EmptyStateView(
                title: "Search for a package",
                message: "Type a name and press Return. Formulae and casks appear here.",
                systemImage: "magnifyingglass")
        } else if model.searchResults.isEmpty {
            EmptyStateView(
                title: "No matches",
                message: "No formula or cask matches \"\(model.lastQuery)\".",
                systemImage: "magnifyingglass")
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.searchResults) { result in
                        resultRow(result)
                        Hairline()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.paperRaised, in: .rect(corners: .fixed(8)))
        }
    }

    private func resultRow(_ result: Homebrew.SearchResult) -> some View {
        let installed = model.isInstalled(result)
        return HStack(spacing: Spacing.s3) {
            Toggle(
                "",
                isOn: Binding(
                    get: { model.selectedToInstall.contains(result.id) },
                    set: { model.setInstallMark(result, on: $0) })
            )
            .labelsHidden()
            .toggleStyle(.checkbox)
            .disabled(installed)
            .accessibilityLabel(installed ? "\(result.name) is installed" : "Install \(result.name)")
            .accessibilityIdentifier("homebrew.install.\(result.id)")
            Text(result.name).font(Typography.row).foregroundStyle(Theme.ink).lineLimit(1)
            Text(result.isCask ? "Cask" : "Formula")
                .font(Typography.caption).foregroundStyle(Theme.inkSecondary)
            Spacer(minLength: Spacing.s2)
            if installed {
                StatusLabel(text: "Installed", systemImage: "checkmark.circle", tone: .neutral)
            }
        }
        .padding(.horizontal, Spacing.s3)
        .padding(.vertical, Spacing.s2)
    }
}
