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
        if report.dryRun { return "Dry run complete" }
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
        SheetFrame {
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
                            ? "would be freed. \(moved) of \(report.results.count) \(report.results.count == 1 ? "item" : "items") would be cleaned. Nothing was deleted."
                            : "freed. \(moved) of \(report.results.count) \(report.results.count == 1 ? "item" : "items") cleaned."
                    )
                    .font(Typography.body)
                    .foregroundStyle(Theme.inkSecondary)
                }
                if !problems.isEmpty {
                    DisclosureGroup("\(problems.count) \(problems.count == 1 ? "item" : "items") not removed") {
                        VStack(spacing: 0) {
                            ForEach(problems, id: \.item.url) { result in
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(result.item.url.lastPathComponent)
                                            .font(Typography.row)
                                            .foregroundStyle(Theme.ink)
                                        Text(Self.reason(result))
                                            .font(Typography.caption)
                                            .foregroundStyle(Theme.inkSecondary)
                                            .help(Self.detail(result.outcome) ?? Self.reason(result))
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
                    SecondaryActionButton(
                        title: "Show audit log",
                        action: { NSWorkspace.shared.open(TestEnvironment.auditLog.url) })
                    Spacer()
                    PrimaryActionButton(
                        title: "Done",
                        shortcut: .return,
                        action: {
                            model.report = nil
                            dismiss()
                        })
                }
            }
        }
    }

    static func reason(_ result: CleanResult) -> String {
        if case .failed = result.outcome { return "Could not remove this item" }
        return RefusalCopy.reason(result.refusal ?? .protectedFolder)
    }

    /// The raw error for a failure, kept in a tooltip so the row stays one line.
    static func detail(_ outcome: CleanOutcome) -> String? {
        if case .failed(let message) = outcome { return message }
        return nil
    }
}
