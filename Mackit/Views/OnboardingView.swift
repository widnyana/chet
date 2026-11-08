import AppKit
import MackitCore
import SwiftUI

struct OnboardingView: View {
    @Environment(ScanModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            Image(systemName: "lock.shield")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(Theme.inkSecondary)
            Text("Mackit needs access to the folders it measures.")
                .font(Typography.title)
                .foregroundStyle(Theme.ink)
            Text(
                "macOS hides caches, Mail downloads, browser data, and some app containers from apps. Mackit reads them on this Mac. Nothing is uploaded."
            )
            .font(Typography.body)
            .foregroundStyle(Theme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                step(1, "Open Privacy and Security settings.")
                Hairline()
                step(2, "Turn on Mackit under Full Disk Access.")
                Hairline()
                step(3, "Come back here. Mackit checks by itself.")
            }
            Button("Open System Settings") {
                model.recordGrantAttempt()
                NSWorkspace.shared.open(FullDiskAccess.settingsURL)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.large)
            .padding(.top, Spacing.s2)
            Button("Continue without access") { model.accessSkipped = true }
                .buttonStyle(.link)
            HStack(spacing: Spacing.s2) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking for access")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .padding(Spacing.s12)
        .frame(maxWidth: 520, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper)
        .task {
            while model.access == .denied && !model.accessSkipped {
                try? await Task.sleep(for: .seconds(1))
                model.refreshAccess()
            }
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
            Text("\(number)")
                .font(Typography.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.inkSecondary)
                .frame(width: 18, alignment: .leading)
            Text(text)
                .font(Typography.body)
                .foregroundStyle(Theme.ink)
            Spacer()
        }
        .padding(.vertical, Spacing.s2)
    }
}
