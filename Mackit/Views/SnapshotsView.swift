import MackitCore
import SwiftUI

struct SnapshotsView: View {
    @Environment(ScanModel.self) private var model

    var body: some View {
        List(model.snapshots, id: \.self) { snapshot in
            Toggle(snapshot.date, isOn: model.isSelected(snapshot))
        }
        .navigationTitle("Time Machine local snapshots")
        .navigationSubtitle("macOS reports their size only when they are deleted")
    }
}
