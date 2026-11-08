import AppKit
import MackitCore
import SwiftUI

/// Non-blocking Full Disk Access notice. Shown once the user has already been sent to
/// Settings, so a macOS relaunch (or a rebuild that voids the ad-hoc grant) never blocks
/// the app behind onboarding again. It re-checks every second and disappears on its own.
struct AccessBanner: View {
    @Environment(ScanModel.self) private var model

    var body: some View {
        if model.showsAccessBanner {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Limited access: caches, Mail downloads and browser data are hidden")
                        .font(.callout)
                    if model.grantAttempts >= 2 {
                        Text(
                            "Mackit may appear more than once in the Full Disk Access list — "
                                + "remove the stale entries, or run: tccutil reset All id.web.widnyana.mackit"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    }
                }
                Spacer()
                Button("Fix") {
                    model.recordGrantAttempt()
                    NSWorkspace.shared.open(FullDiskAccess.settingsURL)
                }
                Button {
                    model.bannerDismissed = true
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help("Hide until the next launch")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.orange.opacity(0.12))
            .overlay(alignment: .bottom) { Divider() }
            .task {
                while !Task.isCancelled && model.showsAccessBanner {
                    try? await Task.sleep(for: .seconds(1))
                    model.refreshAccess()
                }
            }
        }
    }
}
