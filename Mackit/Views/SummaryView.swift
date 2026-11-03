import AppKit
import MackitCore
import SwiftUI

struct SummaryView: View {
    @Environment(ScanModel.self) private var model
    let report: CleanReport
    @State private var appeared = false

    private var problems: [CleanResult] {
        report.results.filter { result in
            switch result.outcome {
            case .removed, .trashed: false
            case .skipped, .failed: true
            }
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: appeared)
            Text(report.freedBytes.formatted(.byteCount(style: .file)))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text("freed. \(report.results.count - problems.count) of \(report.results.count) items cleaned.")
                .foregroundStyle(.secondary)
            if !problems.isEmpty {
                DisclosureGroup("\(problems.count) items left alone") {
                    List(problems, id: \.item.url) { result in
                        VStack(alignment: .leading) {
                            Text(result.item.url.lastPathComponent)
                            Text(Self.reason(result.outcome)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 160)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(model.snapshotErrors, id: \.self) { error in
                Text("Snapshot \(error)").font(.caption).foregroundStyle(.red)
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
        .frame(width: 440)
        .onAppear { appeared = true }
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
