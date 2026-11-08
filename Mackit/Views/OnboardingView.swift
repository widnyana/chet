import AppKit
import MackitCore
import SwiftUI

struct OnboardingView: View {
    @Environment(ScanModel.self) private var model

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Mackit needs Full Disk Access")
                .font(.title2.bold())
            Text(
                "macOS protects caches, Mail downloads and browser data. Without Full Disk Access Mackit cannot see them, so some categories stay empty."
            )
            .multilineTextAlignment(.center)
            .frame(maxWidth: 420)
            .foregroundStyle(.secondary)
            Button("Open Privacy Settings") {
                // Persist before leaving: macOS relaunches the app when the grant
                // applies, and that relaunch must not show this screen again.
                model.recordGrantAttempt()
                NSWorkspace.shared.open(FullDiskAccess.settingsURL)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            Text("Turn on Mackit in the list, then come back here. This window updates by itself.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Continue without Full Disk Access") { model.recordGrantAttempt() }
                .buttonStyle(.link)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            // The probe is the only truth about what this process can read; poll it so
            // the screen dismisses itself the moment access works, no restart needed.
            while model.access == .denied && !model.hasAttemptedGrant {
                try? await Task.sleep(for: .seconds(1))
                model.refreshAccess()
            }
        }
    }
}
