import SwiftUI

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
            Button("None") { selectionActions?.none() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            Button("Invert") { selectionActions?.invert() }
                .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }
}

@main
struct MackitApp: App {
    @State private var model = ScanModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 960, minHeight: 600)
        }
        .commands {
            CommandMenu("Scan") {
                Button(model.isScanning ? "Stop Scan" : "Scan") {
                    if model.isScanning { model.cancel() } else { model.scan() }
                }
                .keyboardShortcut("r")
            }
            SelectCommands()
        }
    }
}
