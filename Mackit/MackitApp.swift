import MackitCore
import SwiftUI

@main
struct MackitApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Mackit \(Mackit.version)")
                .frame(minWidth: 800, minHeight: 500)
        }
    }
}
