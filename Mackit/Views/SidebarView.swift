import MackitCore
import SwiftUI

struct SidebarView: View {
    @Environment(ScanModel.self) private var model
    @Binding var selection: String?
    @Binding var confirming: Bool

    var body: some View {
        List(selection: $selection) {
            Section("Reclaimable") {
                ForEach(model.categories) { category in
                    HStack {
                        Text(category.title)
                        if category.needsFullDiskAccess {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.secondary)
                                .help("Some folders need Full Disk Access")
                        }
                        Spacer()
                        Text(
                            category.id == "snapshots"
                                ? "\(model.snapshots.count)" : category.bytes.formatted(.byteCount(style: .file))
                        )
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    }
                    .tag(category.id)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Text("Selected: \(model.selectedBytes.formatted(.byteCount(style: .file)))")
                    .font(.caption)
                    .monospacedDigit()
                if model.isScanning {
                    ProgressView().controlSize(.small)
                    Button("Stop") { model.cancel() }
                } else if model.isCleaning {
                    ProgressView("Cleaning").controlSize(.small)
                } else {
                    HStack {
                        Button(model.categories.isEmpty ? "Scan" : "Scan again") { model.scan() }
                        Button("Clean") { confirming = true }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.selectedItems.isEmpty && model.selectedSnapshots.isEmpty)
                    }
                }
            }
            .padding()
        }
        .navigationSplitViewColumnWidth(min: 260, ideal: 300)
    }
}
