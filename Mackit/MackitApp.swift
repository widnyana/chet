import SwiftUI

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
        }
    }
}
