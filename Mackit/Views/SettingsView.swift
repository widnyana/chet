import MackitCore
import SwiftUI

/// The app's Settings page (Cmd+,). One opt-in: the duplicates step skips caches,
/// project build dirs, and other temporary places unless the user asks for them.
struct SettingsView: View {
    @Environment(ScanModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Duplicate files") {
                Toggle(isOn: $model.includeTempInDuplicates) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Include caches and build folders")
                        Text(
                            "Search for duplicates inside caches, project build dirs (node_modules, target, .gradle) and other temporary places. Off by default: these folders regenerate, so duplicates there rarely free real space."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 140)
    }
}
