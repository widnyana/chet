import AppKit
import MackitCore
import SwiftUI

struct OnboardingView: View {
    @Environment(ScanModel.self) private var model

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 52))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
            VStack(spacing: 6) {
                Text("Give Mackit Full Disk Access")
                    .font(.title.bold())
                Text(
                    "macOS hides caches, Mail downloads and browser data from apps. Mackit needs access to measure and clean them. Nothing leaves your Mac."
                )
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 440)
            }
            VStack(alignment: .leading, spacing: 14) {
                step(1, "Open Privacy & Security settings")
                step(2, "Turn on Mackit under Full Disk Access")
                step(3, "Come back here. Mackit checks every second")
            }
            .padding(20)
            .frame(maxWidth: 440, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
            Button("Open Settings", systemImage: "gearshape") {
                NSWorkspace.shared.open(FullDiskAccess.settingsURL)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
            HStack(spacing: 6) {
                Circle().fill(.orange).frame(width: 8, height: 8)
                Text("Waiting for access")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if waited > 10 {
                    Text("· enabled but still asking? Quit and reopen Mackit — macOS applies Full Disk Access on relaunch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button("Continue Without Access") {
                    model.skipAccessCheck = true
                    UserDefaults.standard.set(true, forKey: "skipAccessCheck")
                }
                .buttonStyle(.link)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            // The probe is the only truth about what this process can read; poll it so
            // the onboarding self-dismisses the moment access works — no restart needed
            // when macOS applies the grant live.
            while model.access == .denied && !model.skipAccessCheck {
                try? await Task.sleep(for: .seconds(1))
                waited += 1
                model.refreshAccess()
            }
        }
    }

    @State private var waited = 0

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .frame(width: 28, height: 28)
                .background(.tint.opacity(0.15), in: Circle())
            Text(text)
        }
    }
}
