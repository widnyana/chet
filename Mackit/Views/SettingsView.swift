import MackitCore
import SwiftUI

/// SwiftUI's `Settings` scene titles its window "<AppName> Settings" and offers no
/// title modifier. The design language wants the plain word, so the hosting window's
/// title is fixed when the view lands in it.
struct SettingsWindowTitle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { view.window?.title = "Settings" }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { view.window?.title = "Settings" }
    }
}

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
                            .font(Typography.body)
                        Text("Search inside caches and build folders. Off by default.")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.inkSecondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .tint(Theme.accent)
        .frame(width: 420, height: 120)
        .background(SettingsWindowTitle())
    }
}
