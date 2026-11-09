import AppKit
import ChetCore
import SwiftUI

struct OnboardingView: View {
    @Environment(ScanModel.self) private var model

    var body: some View {
        // Scrollable: the permission copy is taller than the minimum window, and a clipped
        // row would hide the next step.
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(Theme.inkSecondary)
                Text("Chet needs permission to find junk.")
                    .font(Typography.title)
                    .foregroundStyle(Theme.ink)
                Text(
                    "macOS keeps some folders private, like caches and Mail downloads. Chet needs Full Disk Access to see them. Your files stay on this Mac."
                )
                .font(Typography.body)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 0) {
                    step(1, "Open Privacy and Security in System Settings.")
                    Hairline()
                    step(2, "Turn on Chet under Full Disk Access.")
                    Hairline()
                    step(3, "Come back here. Chet checks by itself.")
                }
                Button("Open System Settings") {
                    model.recordGrantAttempt()
                    NSWorkspace.shared.open(FullDiskAccess.settingsURL)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.large)
                .padding(.top, Spacing.s2)
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Button("Continue with limited results") { model.accessSkipped = true }
                        .buttonStyle(.link)
                    Text("Without access, Chet finds less. It never removes anything you did not choose.")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
            .frame(maxWidth: .infinity)
        }
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
