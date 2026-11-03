import MackitCore
import SwiftUI

struct SidebarView: View {
    @Environment(ScanModel.self) private var model
    @Binding var selection: String?

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
                        Text(category.bytes.formatted(.byteCount(style: .file)))
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
                } else {
                    Button(model.categories.isEmpty ? "Scan" : "Scan again") { model.scan() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .navigationSplitViewColumnWidth(min: 240, ideal: 280)
    }
}
