import AppKit
import MackitCore
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "trash")
                    .font(.system(size: 34))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remove \(app?.name ?? "this app")?")
                        .font(.title2.bold())
                    Text(
                        "\(model.selectedCount) items · "
                            + model.selectedBytes.formatted(.byteCount(style: .file))
                    )
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
            }
            ScrollView {
                VStack(spacing: 0) {
                    if model.appSelected, let app {
                        row(
                            symbol: "app.dashed", title: app.name,
                            detail: "App bundle", bytes: model.appBytes)
                        Divider()
                    }
                    ForEach(rows) { row in
                        self.row(
                            symbol: "folder", title: row.kind.title,
                            detail: row.count == 1 ? "1 item" : "\(row.count) items", bytes: row.bytes)
                        if row.kind != rows.last?.kind { Divider() }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 220)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 6) {
                Label("The app and selected files move to the Trash", systemImage: "trash")
                Label("Each item is checked again before it moves", systemImage: "checkmark.shield")
                if let app, !model.appSelected, app.isWritable, !model.isRunning {
                    Label("The app bundle stays installed", systemImage: "app.dashed")
                }
            }
            .font(.callout)
            Text("Nothing is deleted permanently. You can restore items from the Trash.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if model.isRunning {
                Label(
                    "Quit the app before removing it.", systemImage: "exclamationmark.triangle.fill"
                )
                .font(.callout.weight(.medium))
                .foregroundStyle(.orange)
            }
            if DryRun.enabled {
                Label("DRY RUN: nothing will be moved", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.large)
                Button("Move to Trash", role: .destructive) {
                    model.remove()
                    dismiss()
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canRemove)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private struct ConfirmRow: Identifiable {
        let kind: AppComponentKind
        let count: Int
        let bytes: Int64
        var id: String { kind.rawValue }
    }

    private func row(symbol: String, title: String, detail: String, bytes: Int64) -> some View {
        HStack {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 22)
            Text(title)
            Spacer()
            Text(detail).font(.caption).foregroundStyle(.secondary)
            Text(bytes.formatted(.byteCount(style: .file)))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)
        }
        .padding(.vertical, 6)
    }
}

struct UninstallSummaryView: View {
    @Environment(AppCleanerModel.self) private var model
    let report: UninstallReport
    @State private var appeared = false

    private var problems: [UninstallResult] {
        report.results.filter { result in
            switch result.outcome {
            case .trashed: false
            case .skipped, .failed: true
            }
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(report.dryRun ? Color.orange : Color.green)
                .symbolEffect(.bounce, value: appeared)
            Text(report.trashedBytes.formatted(.byteCount(style: .file)))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(
                report.dryRun
                    ? "would be moved to the Trash (dry run). \(report.trashedCount) of \(report.results.count) items would be moved. Nothing was moved."
                    : "moved to the Trash. \(report.trashedCount) of \(report.results.count) items moved."
            )
            .foregroundStyle(.secondary)
            if !problems.isEmpty {
                DisclosureGroup("\(problems.count) items left alone") {
                    List(problems) { result in
                        VStack(alignment: .leading) {
                            Text(result.name)
                            Text(Self.reason(result.outcome))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 160)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("Show Audit Log") { NSWorkspace.shared.open(AuditLog().url) }
                Spacer()
                Button("Done") { model.report = nil }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 6)
        }
        .padding(28)
        .frame(width: 460)
        .onAppear { appeared = true }
    }

    static func reason(_ outcome: UninstallOutcome) -> String {
        switch outcome {
        case .trashed: "Moved to the Trash"
        case .skipped(let reason): reason.title
        case .failed(let message): message
        }
    }
}

/// Bulk confirm: the marked apps, the total, and the removal policy. Per-app
/// related-file counts are deliberately not pre-scanned here — the summary sheet
/// reports exactly what moved, per app, after the pass.
struct BulkUninstallConfirmSheet: View {
    @Environment(AppCleanerModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let apps = model.markedAppsList
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "trash")
                    .font(.system(size: 34))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(apps.count == 1 ? "Remove 1 app?" : "Remove \(apps.count) apps?")
                        .font(.title2.bold())
                    Text("\(model.markedBytes.formatted(.byteCount(style: .file))) total")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(apps) { app in
                        HStack(spacing: 10) {
                            Image(nsImage: IconCache.icon(for: app.url))
                                .resizable()
                                .frame(width: 24, height: 24)
                            Text(app.name).lineLimit(1)
                            Spacer()
                            Text(model.locationLabel(app))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(
                                model.appSizes[app.url].map {
                                    $0.formatted(.byteCount(style: .file))
                                } ?? "—"
                            )
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 84, alignment: .trailing)
                        }
                        .padding(.vertical, 6)
                        if app.id != apps.last?.id { Divider() }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 220)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 6) {
                Label(
                    "Each app bundle and its exact-match Library files move to the Trash",
                    systemImage: "trash")
                Label(
                    "Name matches and shared data stay; each item is checked again before it moves",
                    systemImage: "checkmark.shield")
                if model.markedRunningCount > 0 {
                    Label(
                        model.markedRunningCount == 1
                            ? "1 running app will be skipped"
                            : "\(model.markedRunningCount) running apps will be skipped",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                }
            }
            .font(.callout)
            Text("Nothing is deleted permanently. You can restore items from the Trash.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if DryRun.enabled {
                Label("DRY RUN: nothing will be moved", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.large)
                Button("Move \(apps.count) to Trash", role: .destructive) {
                    model.removeMarked()
                    dismiss()
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canBulkRemove)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}

/// Bulk summary: one total, one row per app, and every skipped or failed item with
/// the app it belonged to. Dry run keeps the orange "nothing was moved" contract.
struct BulkUninstallSummaryView: View {
    @Environment(AppCleanerModel.self) private var model
    let report: BulkUninstallReport
    @State private var appeared = false

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
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(report.dryRun ? Color.orange : Color.green)
                .symbolEffect(.bounce, value: appeared)
            Text(report.trashedBytes.formatted(.byteCount(style: .file)))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(summaryLine)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if !problems.isEmpty {
                DisclosureGroup("\(problems.count) items left alone") {
                    List(problems, id: \.result.id) { problem in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(problem.app.name)
                            Text(
                                problem.result.name + " · "
                                    + UninstallSummaryView.reason(problem.result.outcome)
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 160)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("Show Audit Log") { NSWorkspace.shared.open(AuditLog().url) }
                Spacer()
                Button("Done") { model.bulkReport = nil }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 6)
        }
        .padding(28)
        .frame(width: 460)
        .onAppear { appeared = true }
    }

    private var summaryLine: String {
        let apps = report.items.count == 1 ? "1 app" : "\(report.items.count) apps"
        if report.dryRun {
            return
                "would be moved to the Trash (dry run). \(report.trashedCount) of \(report.resultCount) items across \(apps) would be moved. Nothing was moved."
        }
        return "moved to the Trash. \(report.trashedCount) of \(report.resultCount) items across \(apps) moved."
    }
}
