import AppKit
import MackitCore
import SwiftUI

struct ContentView: View {
    @Environment(ScanModel.self) private var model
    @State private var selection: String?

    var body: some View {
        Group {
            if model.access == .denied && !model.skipAccessCheck {
                OnboardingView()
            } else {
                NavigationSplitView {
                    SidebarView(selection: $selection)
                } detail: {
                    if let id = selection, let category = model.categories.first(where: { $0.id == id }) {
                        Text(category.title).font(.title2)
                    } else {
                        ContentUnavailableView(
                            "Pick a category", systemImage: "sidebar.left",
                            description: Text("Run a scan, then pick a category to see its items."))
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshAccess()
        }
    }
}
