import AppKit
import ChetCore
import SwiftUI

struct SummaryView: View {
    @Environment(ScanModel.self) private var model
    // The sheet is owned by ContentView, so clearing the report alone leaves it on screen
    // showing the confirmation again. Done has to dismiss it.
    @Environment(\.dismiss) private var dismiss
    let report: CleanReport

    private var problems: [CleanResult] {
        report.results.filter { result in
            switch result.outcome {
            case .removed, .trashed: false
            case .skipped, .failed: true
            }
        }
    }

    private var moved: Int { report.results.count - problems.count }

    /// The verb comes from what actually happened, so a Trash run never says "Deleted".
    private var title: String {
        if report.dryRun { return "Preview complete" }
        var removed = 0
        var trashed = 0
        for result in report.results {
            switch result.outcome {
            case .removed: removed += 1
            case .trashed: trashed += 1
            case .skipped, .failed: break
            }
        }
        if removed > 0 && trashed > 0 { return "Removed" }
        return trashed > 0 ? "Moved to the Trash" : "Deleted"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(title)
                    .font(Typography.title)
                    .foregroundStyle(Theme.ink)
                Text(report.freedBytes.formatted(.byteCount(style: .file)))
                    .font(Typography.display)
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                Text(
                    report.dryRun
                        ? "would be freed. \(moved) of \(report.results.count) items would be removed. Nothing was deleted."
                        : "freed. \(moved) of \(report.results.count) items removed."
                )
                .font(Typography.body)
                .foregroundStyle(Theme.inkSecondary)
            }
            if !problems.isEmpty {
                DisclosureGroup("\(problems.count) items not removed") {
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
                                        .help(Self.detail(result.outcome) ?? Self.reason(result.outcome))
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
                Button("Show activity log") { NSWorkspace.shared.open(AuditLog().url) }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Done") {
                    model.report = nil
                    dismiss()
                }
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
        case .skipped(.changed): "Changed since the scan"
        case .skipped(.missing): "Already gone"
        case .skipped(.policy): "Protected by Chet"
        case .skipped(.appRunning): "The app is open"
        case .skipped(.localState): "A project is using it"
        case .failed: "Could not remove this item"
        case .removed, .trashed: "Removed"
        }
    }

    /// The raw error for a failure, kept in a tooltip so the row stays one line.
    static func detail(_ outcome: CleanOutcome) -> String? {
        if case .failed(let message) = outcome { return message }
        return nil
    }
}
