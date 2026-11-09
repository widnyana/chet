import ChetCore
import SwiftUI
import os

/// Installs the crash handler and flight recorder at launch, after rotating any stale crash
/// report aside. Order matters: rotation must precede install (see LogMaintenance).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let directory = FlightRecorder.defaultDirectory
        let sawCrash = LogMaintenance.launchCheck(in: directory)
        let recorder = FlightRecorder(directory: directory)
        if sawCrash {
            recorder.record(step: "launch", "previous crash detected")
            Logger(subsystem: "id.web.widnyana.chet", category: "launch").notice(
                "previous crash detected; see ~/Library/Logs/chet/")
        }
        FlightRecorder.shared = recorder
        CrashHandler.install(directory: directory, recorder: recorder)
    }
}

/// Select All / None / Invert for the visible category list, via keyboard.
struct SelectionActions {
    let all: () -> Void
    let none: () -> Void
    let invert: () -> Void
}

private struct SelectionActionsKey: FocusedValueKey {
    typealias Value = SelectionActions
}

extension FocusedValues {
    var selectionActions: SelectionActions? {
        get { self[SelectionActionsKey.self] }
        set { self[SelectionActionsKey.self] = newValue }
    }
}

struct SelectCommands: Commands {
    @FocusedValue(\.selectionActions) private var selectionActions

    var body: some Commands {
        CommandMenu("Select") {
            Button("All") { selectionActions?.all() }
                .keyboardShortcut("a", modifiers: .command)
                .disabled(selectionActions == nil)
            Button("None") { selectionActions?.none() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(selectionActions == nil)
            Button("Invert") { selectionActions?.invert() }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(selectionActions == nil)
        }
    }
}

/// Replaces the system About panel with the app's own window, which can show
/// the build facts, machine facts, access grant, and log paths.
private struct AboutCommand: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Chet") { openWindow(id: AboutView.windowID) }
        }
    }
}

@main
struct ChetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = ScanModel()
    @State private var tweaks = TweaksModel()

    var body: some Scene {
        WindowGroup("Chet") {
            ContentView()
                .environment(model)
                .environment(tweaks)
                .frame(minWidth: 960, minHeight: 632)
        }
        .commands {
            AboutCommand()
            CommandMenu("Scan") {
                Button(model.isScanning ? "Stop scan" : "Scan") {
                    if model.isScanning { model.cancel() } else { model.scan() }
                }
                .keyboardShortcut("r")
                .disabled(model.access == .denied && !model.accessSkipped)
            }
            SelectCommands()
        }
        // One About window, opened from Chet > About Chet. Separate from the
        // main window so it can stay open while the ledger runs.
        Window("About Chet", id: AboutView.windowID) {
            AboutView()
                .environment(model)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands { AboutCommand() }
        // The standard macOS Settings scene: "Settings…" in the app menu, Cmd+, opens it.
        Settings {
            SettingsView()
                .environment(model)
                .environment(tweaks)
        }
        .windowResizability(.contentSize)
        .commands { AboutCommand() }
    }
}
