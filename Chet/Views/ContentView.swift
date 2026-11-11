import AppKit
import ChetCore
import SwiftUI

struct ContentView: View {
    @Environment(ScanModel.self) private var model
    @Environment(TweaksModel.self) private var tweaks
    @Environment(MiseModel.self) private var mise
    @State private var appCleaner = AppCleanerModel()
    @State private var homebrew = HomebrewModel()
    @State private var goModules = GoModulesModel()
    @State private var selection: String? = "overview"
    @State private var confirming = false
    @State private var systemStatus = SystemStatusModel()
    @State private var pageWidth: CGFloat = 0

    var body: some View {
        Group {
            if model.access == .denied && !model.accessSkipped && !model.accessWasGranted {
                OnboardingView()
            } else {
                NavigationSplitView {
                    SidebarView(selection: $selection)
                        .safeAreaBar(edge: .bottom, spacing: 0) {
                            SidebarFooter()
                        }
                } detail: {
                    detail
                        .safeAreaInset(edge: .top, spacing: 0) {
                            // Tweaks owns its own gate and disables the cleaning strip.
                            if selection != "tweaks" {
                                TopStatusStrip(
                                    showsScanResult: !["applications", "homebrew", "go"].contains(selection ?? ""))
                            }
                        }
                        .toolbar {
                            if !["applications", "tweaks", "homebrew", "go"]
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
        .environment(goModules)
        .environment(systemStatus)
        .onAppear {
            if !goModules.isAvailable {
                goModules.detect()
            }
        }
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
            if !goModules.isAvailable {
                goModules.detect()
            }
        }
        .onChange(of: selection) { _, newValue in
            guard let code = Self.viewCode(for: newValue) else { return }
            VerboseLog.event(.debug, .ui, .uiNavigationChanged, .code(.view, code))
        }
        .onChange(of: confirming) { _, showing in
            if showing {
                VerboseLog.event(.debug, .ui, .uiSheetPresented, .code(.sheet, .sheetConfirm))
            }
        }
    }

    static func viewCode(for selection: String?) -> LogCode? {
        switch selection {
        case "overview": .viewHome
        case "applications": .viewApps
        case "homebrew": .viewHomebrew
        case "disk-map": .viewStorage
        case "tweaks": .viewTweaks
        case "settings": .viewSettings
        case "snapshots": .viewSnapshots
        case "mise": .viewMise
        case "go": .viewGo
        case "about": .viewAbout
        default: nil
        }
    }

    @ViewBuilder private var detail: some View {
        if selection == "applications" {
            UninstallWorkspace()
        } else if selection == "disk-map" {
            DiskMapView(destination: $selection)
        } else if selection == "tweaks" {
            TweaksView()
        } else if selection == "snapshots" {
            SnapshotsView(onClean: {
                model.beginClean(nil)
                confirming = true
            })
        } else if selection == "homebrew" {
            HomebrewView()
        } else if selection == "mise", mise.isAvailable {
            MiseView()
        } else if selection == "go" {
            GoModulesView()
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
