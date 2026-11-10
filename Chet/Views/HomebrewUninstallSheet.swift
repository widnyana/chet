import ChetCore
import SwiftUI

/// The review step before Homebrew removes a package. It names every package, its kind,
/// version, and size, and offers the cask data deletion only when a cask is selected.
struct HomebrewUninstallSheet: View {
    @Environment(HomebrewModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var deleteData = false

    private var packages: [BrewPackage] {
        model.markedPackages.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    private var hasCask: Bool { packages.contains { $0.kind == .cask } }

    var body: some View {
        SheetFrame {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text(
                        packages.count == 1
                            ? "Uninstall 1 package?" : "Uninstall \(packages.count) packages?"
                    )
                    .font(Typography.title)
                    .foregroundStyle(Theme.ink)
                    Text(
                        "\(packages.count) \(packages.count == 1 ? "package" : "packages") · \(model.markedBytes.formatted(.byteCount(style: .file)))"
                    )
                    .font(Typography.body)
                    .monospacedDigit()
                    .foregroundStyle(Theme.inkSecondary)
                }

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(packages) { package in
                            HStack(spacing: Spacing.s2) {
                                Text(package.title)
                                    .font(Typography.row)
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(1)
                                Spacer(minLength: Spacing.s2)
                                Text("\(package.kindLabel) · \(package.version)")
                                    .font(Typography.caption)
                                    .foregroundStyle(Theme.inkSecondary)
                                    .lineLimit(1)
                                Text(package.size.formatted(.byteCount(style: .file)))
                                    .font(Typography.row)
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.inkSecondary)
                                    .frame(width: 80, alignment: .trailing)
                            }
                            .padding(.vertical, Spacing.s1)
                            if package.id != packages.last?.id { Hairline() }
                        }
                    }
                    .padding(.horizontal, Spacing.s3)
                    .padding(.vertical, Spacing.s2)
                }
                .frame(maxHeight: 220)
                .background(Theme.paperRaised, in: .rect(corners: .fixed(6)))

                if hasCask {
                    VStack(alignment: .leading, spacing: Spacing.s1) {
                        Toggle("Uninstall and delete data", isOn: $deleteData)
                            .font(Typography.body)
                        Text("Removes settings and saved files for casks. This cannot be undone.")
                            .font(Typography.caption)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }

                if DryRun.enabled {
                    StatusLabel(
                        text: "Preview only. Nothing will be removed.",
                        systemImage: "exclamationmark.triangle",
                        tone: .amber)
                }

                HStack {
                    Spacer()
                    SecondaryActionButton(title: "Cancel", shortcut: .return, action: { dismiss() })
                    DestructiveActionButton(
                        title: "Uninstall",
                        isEnabled: model.canAct && !packages.isEmpty,
                        help: "Uninstall the selected Homebrew packages",
                        accessibilityLabel: "Uninstall \(packages.count) packages",
                        action: {
                            model.uninstall(zap: deleteData)
                            dismiss()
                        })
                }
            }
            .onExitCommand { dismiss() }
        }
    }
}
