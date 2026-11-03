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
        VStack(alignment: .leading, spacing: 12) {
            Text("Freed \(report.freedBytes.formatted(.byteCount(style: .file)))").font(.title.bold())
            Text("\(report.results.count - problems.count) of \(report.results.count) items cleaned.")
                .foregroundStyle(.secondary)
            if !problems.isEmpty {
                Text("Not cleaned").font(.headline)
                List(problems, id: \.item.url) { result in
                    VStack(alignment: .leading) {
                        Text(result.item.url.lastPathComponent)
                        Text(Self.reason(result.outcome)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 160)
            }
            ForEach(model.snapshotErrors, id: \.self) { error in
                Text("Snapshot \(error)").font(.caption).foregroundStyle(.red)
            }
            HStack {
                Button("Open audit log") { NSWorkspace.shared.open(AuditLog().url) }
                Spacer()
                Button("Done") { model.report = nil }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    static func reason(_ outcome: CleanOutcome) -> String {
        switch outcome {
        case .skipped(.changed): "Changed since the scan, left alone"
        case .skipped(.missing): "Already gone"
        case .skipped(.policy): "Protected location, left alone"
        case .skipped(.appRunning): "Its app is running. Quit the app and clean again"
        case .failed(let message): message
        case .removed, .trashed: "Cleaned"
        }
    }
}
