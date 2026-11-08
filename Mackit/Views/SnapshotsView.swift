import MackitCore
import SwiftUI

struct SnapshotsView: View {
    @Environment(ScanModel.self) private var model
    let onClean: () -> Void
    @State private var newestFirst = true

    var body: some View {
        Group {
            if model.snapshots.isEmpty && !model.isScanning {
                ContentUnavailableView {
                    Label("No local snapshots", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text(
                        "Time Machine keeps local snapshots on the disk when it has room. Run a scan to check for them."
                    )
                } actions: {
                    Button("Scan Now") { model.scan() }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                }
            } else {
                List(model.snapshots.sorted { newestFirst ? $0.date > $1.date : $0.date < $1.date }, id: \.self) {
                    snapshot in
                    Toggle(snapshot.date, isOn: model.isSelected(snapshot))
                }
            }
        }
        .safeAreaInset(edge: .bottom) { selectionBar }
        .navigationTitle("Time Machine local snapshots")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newestFirst.toggle()
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .help(newestFirst ? "Sorted newest first" : "Sorted oldest first")
            }
        }
    }

    /// Same centered-capsule grammar as the category ActionBar; macOS reports snapshot
    /// sizes only when they are deleted, so the bar shows counts, not bytes.
    private var selectionBar: some View {
        let count = model.selectedSnapshots.count
        return HStack {
            Spacer()
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(count == 1 ? "1 snapshot selected" : "\(count) snapshots selected")
                        .font(.headline)
                        .monospacedDigit()
                    Text("macOS reports their size only when they are deleted")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Clean Selected", systemImage: "sparkles") { onClean() }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(count == 0 || model.isCleaning)
            }
            .padding(.leading, 18)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
            Spacer()
        }
        .padding(.bottom, 16)
    }
}
