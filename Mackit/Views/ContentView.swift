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
                    VStack(spacing: 0) {
                        AccessBanner()
                        detail
                    }
                    .toolbar {
                        if selection != "apps" {
                            scanButton
                        }
                    }
                }
            }
        }
        .environment(appCleaner)
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
        // Below the toolbar, above the content: an overlay at .top would sit on the
        // title bar and cover the scan pill. Uninstall surfaces never scan, so the
        // toast stays off them.
        .safeAreaInset(edge: .top, spacing: 0) {
            if selection != "apps" { ScanFinishedToast() }
        }
        .overlay(alignment: .bottomLeading) { dryRunBadge }
        .onChange(of: selection) { _, next in
            if next == "apps" { appCleaner.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshAccess()
            if selection == "apps" {
                appCleaner.hasFullDiskAccess = FullDiskAccess.status() == .granted
                appCleaner.refreshRunningState()
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if selection == "apps" {
            UninstallWorkspace()
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
            OverviewView(selection: $selection, onClean: { confirming = true })
        }
    }

    /// Shown only in debug builds while DRY_RUN is engaged — cleaning is simulated.
    @ViewBuilder private var dryRunBadge: some View {
        #if DEBUG
            if DryRun.enabled {
                Label("DRY RUN ENGAGED", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .foregroundStyle(.orange)
                    .background(.orange.opacity(0.15), in: .capsule)
                    .overlay(.orange.opacity(0.4), in: .capsule)
                    .padding(.bottom, 12)
                    .padding(.leading, 16)
                    .help("DRY_RUN is set: cleaning reports success but no files are removed. Debug builds only.")
            }
        #endif
    }

    @ToolbarContentBuilder private var scanButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            ScanStatusView()
        }
    }
}
