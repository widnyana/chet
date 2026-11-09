import AppKit
import ChetCore
import SwiftUI

struct AppUninstallConfirmSheet: View {
    @Environment(AppCleanerModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let app = model.selectedApp
        let rows = Dictionary(grouping: model.selectedComponentList, by: \.kind)
            .map { ConfirmRow(kind: $0.key, count: $0.value.count, bytes: $0.value.reduce(0) { $0 + $1.bytes }) }
            .sorted {
                (AppComponentKind.allCases.firstIndex(of: $0.kind) ?? Int.max)
                    < (AppComponentKind.allCases.firstIndex(of: $1.kind) ?? Int.max)
            }
        VStack(alignment: .leading, spacing: Spacing.s4) {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text("Move \(app?.name ?? "this app") to the Trash?")
                    .font(Typography.title)
                    .foregroundStyle(Theme.ink)
                Text(
                    "\(model.selectedCount) items · \(model.selectedBytes.formatted(.byteCount(style: .file)))"
                )
                .font(Typography.body)
                .monospacedDigit()
                .foregroundStyle(Theme.inkSecondary)
            }
            ScrollView {
                VStack(spacing: 0) {
                    if model.appSelected, let app {
                        confirmRow(
                            symbol: "app.dashed", title: app.name,
                            detail: AppCopy.component(.application),
                            bytes: model.appBytes)
                        Hairline()
                    }
                    ForEach(rows) { row in
                        confirmRow(
                            symbol: "folder", title: AppCopy.component(row.kind),
                            detail: row.count == 1 ? "1 item" : "\(row.count) items", bytes: row.bytes)
                        if row.kind != rows.last?.kind { Hairline() }
                    }
                }
                .padding(.horizontal, Spacing.s3)
                .padding(.vertical, Spacing.s2)
            }
            .frame(maxHeight: 220)
            .background(Theme.paperRaised, in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: Spacing.s2) {
                labeled("The app and the files you chose move to the Trash.", icon: "trash")
                labeled("You can restore them from the Trash.", icon: "arrow.uturn.backward")
                labeled("Chet checks each item again before it moves.", icon: "checkmark.shield")
                if let app, !model.appSelected, app.isWritable, !model.isRunning {
                    labeled("The app stays installed.", icon: "app.dashed")
                }
            }
            if model.isRunning {
                StatusLabel(
                    text: "Quit the app before removing it.",
                    systemImage: "exclamationmark.triangle",
                    tone: .amber)
            }
            if DryRun.enabled {
                StatusLabel(
                    text: "Preview only. Nothing will be moved.",
                    systemImage: "exclamationmark.triangle",
                    tone: .amber)
            }
            HStack {
                Spacer()
                SecondaryActionButton(title: "Cancel", shortcut: .escape, action: { dismiss() })
                DestructiveActionButton(
                    title: "Move to Trash",
                    isEnabled: model.canRemove,
                    shortcut: .return,
                    action: {
                        model.remove()
                        dismiss()
                    })
            }
        }
        .padding(Spacing.s6)
        .frame(width: 520)
        .background(Theme.paper)
    }

    private struct ConfirmRow: Identifiable {
        let kind: AppComponentKind
        let count: Int
        let bytes: Int64
        var id: String { kind.rawValue }
    }

    private func confirmRow(symbol: String, title: String, detail: String, bytes: Int64) -> some View {
        HStack(spacing: Spacing.s2) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.inkSecondary)
                .frame(width: 22)
            Text(title)
                .font(Typography.row)
                .foregroundStyle(Theme.ink)
            Spacer()
            Text(detail)
                .font(Typography.caption)
                .foregroundStyle(Theme.inkSecondary)
            Text(bytes.formatted(.byteCount(style: .file)))
                .font(Typography.row)
                .monospacedDigit()
                .foregroundStyle(Theme.inkSecondary)
                .frame(width: 88, alignment: .trailing)
        }
        .padding(.vertical, Spacing.s1)
    }

    private func labeled(_ text: String, icon: String) -> some View {
        HStack(spacing: Spacing.s2) {
            Image(systemName: icon)
                .foregroundStyle(Theme.inkSecondary)
            Text(text)
                .font(Typography.body)
                .foregroundStyle(Theme.ink)
        }
    }
}

struct UninstallSummaryView: View {
    @Environment(AppCleanerModel.self) private var model
    let report: UninstallReport

    private var problems: [UninstallResult] {
        report.results.filter { result in
            switch result.outcome {
            case .trashed: false
            case .skipped, .failed: true
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(report.dryRun ? "Preview complete" : "Moved to the Trash")
                    .font(Typography.title)
                    .foregroundStyle(Theme.ink)
                Text(report.trashedBytes.formatted(.byteCount(style: .file)))
                    .font(Typography.display)
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                Text(
                    report.dryRun
                        ? "would be moved to the Trash. \(report.trashedCount) of \(report.results.count) items would be moved. Nothing was moved."
                        : "moved to the Trash. \(report.trashedCount) of \(report.results.count) items moved."
                )
                .font(Typography.body)
                .foregroundStyle(Theme.inkSecondary)
            }
            if !problems.isEmpty {
                DisclosureGroup("\(problems.count) items not moved") {
                    VStack(spacing: 0) {
                        ForEach(problems) { result in
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(result.name)
                                        .font(Typography.row)
                                        .foregroundStyle(Theme.ink)
                                    Text(Self.reason(result.outcome))
                                        .font(Typography.caption)
                                        .foregroundStyle(Theme.inkSecondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, Spacing.s1)
                            Hairline()
                        }
                    }
                }
            }
            HStack {
                SecondaryActionButton(
                    title: "Show activity log",
                    action: { NSWorkspace.shared.open(AuditLog().url) })
                Spacer()
                PrimaryActionButton(
                    title: "Done",
                    shortcut: .return,
                    action: { model.report = nil })
            }
        }
        .padding(Spacing.s6)
        .frame(width: 520)
        .background(Theme.paper)
    }

    static func reason(_ outcome: UninstallOutcome) -> String {
        switch outcome {
        case .trashed: "Moved to the Trash"
        case .skipped(let reason): AppCopy.skip(reason)
        case .failed(let message): message
        }
    }
}

struct BulkUninstallConfirmSheet: View {
    @Environment(AppCleanerModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let apps = model.markedAppsList
        VStack(alignment: .leading, spacing: Spacing.s4) {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(apps.count == 1 ? "Move 1 app to the Trash?" : "Move \(apps.count) apps to the Trash?")
                    .font(Typography.title)
                    .foregroundStyle(Theme.ink)
                Text("\(model.markedBytes.formatted(.byteCount(style: .file))) total")
                    .font(Typography.body)
                    .monospacedDigit()
                    .foregroundStyle(Theme.inkSecondary)
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(apps) { app in
                        HStack(spacing: Spacing.s2) {
                            Image(nsImage: IconCache.icon(for: app.url))
                                .resizable()
                                .frame(width: 22, height: 22)
                            Text(app.name)
                                .font(Typography.row)
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                            Spacer()
                            Text(model.locationLabel(app))
                                .font(Typography.caption)
                                .foregroundStyle(Theme.inkSecondary)
                                .lineLimit(1)
                            Text(
                                model.appSizes[app.url].map {
                                    $0.formatted(.byteCount(style: .file))
                                } ?? "n/a"
                            )
                            .font(Typography.row)
                            .monospacedDigit()
                            .foregroundStyle(Theme.inkSecondary)
                            .frame(width: 84, alignment: .trailing)
                        }
                        .padding(.vertical, Spacing.s1)
                        if app.id != apps.last?.id { Hairline() }
                    }
                }
                .padding(.horizontal, Spacing.s3)
                .padding(.vertical, Spacing.s2)
            }
            .frame(maxHeight: 220)
            .background(Theme.paperRaised, in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: Spacing.s2) {
                labeled("The apps and the files you chose move to the Trash.", icon: "trash")
                labeled("You can restore them from the Trash.", icon: "arrow.uturn.backward")
                labeled("Chet checks each item again before it moves.", icon: "checkmark.shield")
                if model.markedRunningCount > 0 {
                    StatusLabel(
                        text: "Running apps are skipped.",
                        systemImage: "exclamationmark.triangle",
                        tone: .amber)
                }
            }
            if DryRun.enabled {
                StatusLabel(
                    text: "Preview only. Nothing will be moved.",
                    systemImage: "exclamationmark.triangle",
                    tone: .amber)
            }
            HStack {
                Spacer()
                SecondaryActionButton(title: "Cancel", shortcut: .escape, action: { dismiss() })
                DestructiveActionButton(
                    title: "Move to Trash",
                    isEnabled: model.canBulkRemove,
                    shortcut: .return,
                    action: {
                        model.removeMarked()
                        dismiss()
                    })
            }
        }
        .padding(Spacing.s6)
        .frame(width: 520)
        .background(Theme.paper)
    }

    private func labeled(_ text: String, icon: String) -> some View {
        HStack(spacing: Spacing.s2) {
            Image(systemName: icon)
                .foregroundStyle(Theme.inkSecondary)
            Text(text)
                .font(Typography.body)
                .foregroundStyle(Theme.ink)
        }
    }
}

struct BulkUninstallSummaryView: View {
    @Environment(AppCleanerModel.self) private var model
    let report: BulkUninstallReport

    private var problems: [(app: InstalledApp, result: UninstallResult)] {
        report.items.flatMap { item in
            item.report.results
                .filter { result in
                    switch result.outcome {
                    case .trashed: false
                    case .skipped, .failed: true
                    }
                }
                .map { (item.app, $0) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(report.dryRun ? "Preview complete" : "Moved to the Trash")
                    .font(Typography.title)
                    .foregroundStyle(Theme.ink)
                Text(report.trashedBytes.formatted(.byteCount(style: .file)))
                    .font(Typography.display)
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                Text(summaryLine)
                    .font(Typography.body)
                    .foregroundStyle(Theme.inkSecondary)
            }
            if !problems.isEmpty {
                DisclosureGroup("\(problems.count) items not moved") {
                    VStack(spacing: 0) {
                        ForEach(problems.indices, id: \.self) { index in
                            let problem = problems[index]
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(problem.app.name)
                                        .font(Typography.row)
                                        .foregroundStyle(Theme.ink)
                                    Text(
                                        problem.result.name + " · "
                                            + UninstallSummaryView.reason(problem.result.outcome)
                                    )
                                    .font(Typography.caption)
                                    .foregroundStyle(Theme.inkSecondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, Spacing.s1)
                            Hairline()
                        }
                    }
                }
            }
            HStack {
                SecondaryActionButton(
                    title: "Show activity log",
                    action: { NSWorkspace.shared.open(AuditLog().url) })
                Spacer()
                PrimaryActionButton(
                    title: "Done",
                    shortcut: .return,
                    action: { model.bulkReport = nil })
            }
        }
        .padding(Spacing.s6)
        .frame(width: 520)
        .background(Theme.paper)
    }

    private var summaryLine: String {
        let apps = report.items.count == 1 ? "1 app" : "\(report.items.count) apps"
        if report.dryRun {
            return
                "would be moved to the Trash. \(report.trashedCount) of \(report.resultCount) items across \(apps) would be moved. Nothing was moved."
        }
        return "moved to the Trash. \(report.trashedCount) of \(report.resultCount) items across \(apps) moved."
    }
}
