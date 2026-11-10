import AppKit
import ChetCore
import SwiftUI

struct ContentView: View {
    @Environment(ScanModel.self) private var model
    @Environment(TweaksModel.self) private var tweaks
    @State private var appCleaner = AppCleanerModel()
    @State private var homebrew = HomebrewModel()
    @State private var selection: String? = "overview"
    @State private var confirming = false
    @State private var systemStatus = SystemStatusModel()
    @State private var pageWidth: CGFloat = 0

    var body: some View {
        Group {
            if model.access == .denied && !model.accessSkipped {
                OnboardingView()
            } else {
                NavigationSplitView {
                    SidebarView(selection: $selection)
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            SidebarFooter()
                        }
                } detail: {
                    detail
                        .safeAreaInset(edge: .top, spacing: 0) {
                            // Tweaks owns its own gate and disables the cleaning strip.
                            if selection != "tweaks" {
                                TopStatusStrip(
                                    gateText: selection == "applications"
                                        ? "Preview only. Nothing will be moved."
                                        : "Preview only. Nothing will be removed.",
                                    showsScanResult: !["applications", "homebrew"].contains(selection ?? ""))
                            }
                        }
                        .toolbar {
                            if !["overview", "applications", "tweaks", "homebrew"]
                                .contains(selection ?? "")
                            {
                                scanButton
                            }
                        }
                }
            }
        }
        .environment(
            \.pageMargin,
            pageWidth >= 1100 ? Metrics.widePageMargin : Metrics.pageMargin
        )
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            pageWidth = width
        }
        .environment(appCleaner)
        .environment(homebrew)
        .environment(systemStatus)
        .sheet(isPresented: $confirming) {
            CleanFlowSheet()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshAccess()
            if selection == "applications" {
                appCleaner.hasFullDiskAccess = FullDiskAccess.status() == .granted
                appCleaner.refreshRunningState()
            }
            if selection == "tweaks" {
                Task { await tweaks.reload() }
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if selection == "applications" {
            UninstallWorkspace()
        } else if selection == "disk-map" {
            DiskMapView()
        } else if selection == "tweaks" {
            TweaksView()
        } else if selection == "snapshots" {
            SnapshotsView(onClean: {
                model.beginClean(nil)
                confirming = true
            })
        } else if selection == "homebrew" {
            HomebrewView()
        } else if let id = selection, let category = model.categories.first(where: { $0.id == id }) {
            CategoryDetailView(category: category, onClean: { confirming = true }, onBack: { selection = "overview" })
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
