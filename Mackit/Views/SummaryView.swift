import AppKit
import MackitCore
import SwiftUI

struct SummaryView: View {
    @Environment(ScanModel.self) private var model
    let report: CleanReport

    private var problems: [CleanResult] {
        report.results.filter { result in
            switch result.outcome {
            case .removed, .trashed: false
            case .skipped, .failed: true
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(report.dryRun ? "Dry run complete" : "Clean complete")
                    .font(Typography.title)
                    .foregroundStyle(Theme.ink)
                Text(report.freedBytes.formatted(.byteCount(style: .file)))
                    .font(Typography.display)
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                Text(
                    report.dryRun
                        ? "would be freed. \(report.results.count - problems.count) of \(report.results.count) items would be cleaned. Nothing was deleted."
                        : "freed. \(report.results.count - problems.count) of \(report.results.count) items cleaned."
                )
                .font(Typography.body)
                .foregroundStyle(Theme.inkSecondary)
            }
            if !problems.isEmpty {
                DisclosureGroup("\(problems.count) items left alone") {
                    VStack(spacing: 0) {
                        ForEach(problems, id: \.item.url) { result in
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(result.item.url.lastPathComponent)
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
            if !model.snapshotErrors.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    ForEach(model.snapshotErrors, id: \.self) { error in
                        StatusLabel(text: error, systemImage: "exclamationmark.triangle", tone: .red)
                    }
                }
            }
            HStack {
                Button("Show audit log") { NSWorkspace.shared.open(AuditLog().url) }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Done") { model.report = nil }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.s6)
        .frame(width: 520)
        .background(Theme.paper)
    }

    static func reason(_ outcome: CleanOutcome) -> String {
        switch outcome {
        case .skipped(.changed): "Changed since the scan, left alone"
        case .skipped(.missing): "Already gone"
        case .skipped(.policy): "Protected location, left alone"
        case .skipped(.appRunning): "Its app is running. Quit it and clean again"
        case .failed(let message): message
        case .removed, .trashed: "Cleaned"
        }
    }
}
