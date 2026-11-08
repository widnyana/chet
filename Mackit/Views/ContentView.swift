import AppKit
import MackitCore
import SwiftUI

struct ContentView: View {
    @Environment(ScanModel.self) private var model
    @State private var selection: String? = "overview"
    @State private var confirming = false

    var body: some View {
        Group {
            if model.access == .denied && !model.hasAttemptedGrant {
                OnboardingView()
            } else {
                NavigationSplitView {
                    SidebarView(selection: $selection)
                } detail: {
                    VStack(spacing: 0) {
                        AccessBanner()
                        detail
                    }
                    .toolbar { scanButton }
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
        .overlay(alignment: .top) { ScanFinishedToast().padding(.top, 8) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshAccess()
        }
    }

    @ViewBuilder private var detail: some View {
        if selection == "disk-map" {
            DiskMapView()
        } else if selection == "snapshots" {
            SnapshotsView(onClean: {
                model.beginClean(nil)
                confirming = true
            })
        } else if let id = selection, let category = model.categories.first(where: { $0.id == id }) {
            CategoryDetailView(category: category, onClean: { confirming = true })
        } else {
            OverviewView(selection: $selection, onClean: { confirming = true })
        }
    }

    @ToolbarContentBuilder private var scanButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            ScanStatusView()
        }
    }
}
