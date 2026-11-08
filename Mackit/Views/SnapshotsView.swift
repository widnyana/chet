import MackitCore
import SwiftUI

struct SnapshotsView: View {
    @Environment(ScanModel.self) private var model
    let onClean: () -> Void
    @State private var newestFirst = true

    var body: some View {
        List(model.snapshots.sorted { newestFirst ? $0.date > $1.date : $0.date < $1.date }, id: \.self) {
            snapshot in
            Toggle(snapshot.date, isOn: model.isSelected(snapshot))
        }
        .navigationTitle("Time Machine local snapshots")
        .navigationSubtitle("macOS reports their size only when they are deleted")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newestFirst.toggle()
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .help(newestFirst ? "Sorted newest first" : "Sorted oldest first")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Clean Selected") { onClean() }
                    .disabled(model.selectedSnapshots.isEmpty)
            }
        }
    }
}
