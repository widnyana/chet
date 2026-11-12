import ChetCore
import SwiftUI

enum CoverageCopy {
    static func caption(_ report: CoverageReport) -> String {
        let accounted = report.used - report.unaccounted
        return
            "Accounted for \(accounted.formatted(.byteCount(style: .file))) of \(report.used.formatted(.byteCount(style: .file))). The rest is space macOS does not report."
    }

    static let hiddenHeading = "Hidden"
    static let excludedHeading = "Excluded"
    static let unaccountedHeading = "Not reported"
}

struct CoverageSheet: View {
    @Environment(\.dismiss) private var dismiss
    let report: CoverageReport

    var body: some View {
        SheetFrame(width: Metrics.sheetWidth, height: Metrics.coverageSheetHeight) {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                Text(CoverageCopy.caption(report))
                    .font(Typography.body)
                    .foregroundStyle(Theme.ink)
                if !report.hidden.isEmpty {
                    section(CoverageCopy.hiddenHeading, report.hidden)
                }
                if !report.excluded.isEmpty {
                    section(CoverageCopy.excludedHeading, report.excluded)
                }
                HStack {
                    Text(CoverageCopy.unaccountedHeading)
                        .font(Typography.row)
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    SizeColumn(bytes: report.unaccounted)
                }
                Spacer()
                HStack {
                    Spacer()
                    PrimaryActionButton(
                        title: "Done",
                        shortcut: .return,
                        action: { dismiss() })
                }
            }
        }
    }

    private func section(_ title: String, _ buckets: [CoverageReport.Bucket]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text(title)
                .font(Typography.section)
                .foregroundStyle(Theme.ink)
            ForEach(Array(buckets.enumerated()), id: \.offset) { _, bucket in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(bucket.label)
                            .font(Typography.row)
                            .foregroundStyle(Theme.ink)
                        Text(bucket.reason)
                            .font(Typography.caption)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    Spacer()
                    SizeColumn(bytes: bucket.bytes)
                }
            }
        }
    }
}
