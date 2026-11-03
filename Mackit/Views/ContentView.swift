import AppKit
import MackitCore
import SwiftUI

struct ContentView: View {
    @Environment(ScanModel.self) private var model
    @State private var selection: String?
    @State private var confirming = false

    var body: some View {
        Group {
            if model.access == .denied && !model.skipAccessCheck {
                OnboardingView()
            } else {
                NavigationSplitView {
                    SidebarView(selection: $selection, confirming: $confirming)
                } detail: {
                    detail
                }
            }
        }
        .sheet(isPresented: $confirming) {
            ConfirmSheet()
        }
        .sheet(
            isPresented: Binding(
                get: { model.report != nil },
                set: { if !$0 { model.report = nil } })
        ) {
            if let report = model.report { SummaryView(report: report) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshAccess()
        }
    }

    @ViewBuilder private var detail: some View {
        if selection == "snapshots" {
            SnapshotsView()
        } else if let id = selection, let category = model.categories.first(where: { $0.id == id }) {
            CategoryDetailView(category: category)
        } else {
            ContentUnavailableView(
                "Pick a category", systemImage: "sidebar.left",
                description: Text("Run a scan, then pick a category to see its items."))
        }
    }
}
