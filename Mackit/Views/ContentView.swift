import AppKit
import MackitCore
import SwiftUI

struct ContentView: View {
    @Environment(ScanModel.self) private var model
    @State private var appCleaner = AppCleanerModel()
    @State private var selection: String? = "overview"
    @State private var confirming = false

    var body: some View {
        Group {
            if model.access == .denied && !model.accessSkipped {
                OnboardingView()
            } else {
                NavigationSplitView {
                    SidebarView(selection: $selection)
                } detail: {
                    detail
                        .safeAreaInset(edge: .top, spacing: 0) {
                            TopStatusStrip()
                        }
                        .background(Theme.paper)
                        .toolbar {
                            if selection != "applications" {
                                scanButton
                            }
                        }
                }
            }
        }
        .environment(appCleaner)
        .tint(Theme.accent)
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
            if selection == "applications" {
                appCleaner.hasFullDiskAccess = FullDiskAccess.status() == .granted
                appCleaner.refreshRunningState()
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if selection == "applications" {
            UninstallWorkspace(onDone: { selection = "overview" })
        } else if selection == "disk-map" {
            DiskMapView()
        } else if selection == "snapshots" {
            SnapshotsView(onClean: {
                model.beginClean(nil)
                confirming = true
            })
        } else if let id = selection, let category = model.categories.first(where: { $0.id == id }) {
            CategoryDetailView(category: category, onClean: { confirming = true })
        } else {
            OverviewView(
                selection: $selection,
                onClean: { confirming = true })
        }
    }

    @ToolbarContentBuilder private var scanButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            ScanStatusView()
        }
    }
}
