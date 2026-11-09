import SwiftUI

/// Full-width action bar at the bottom of a content area. The same component is
/// used by categories, snapshots, the app browser, and app detail.
struct CommandBar: View {
    let metric: String
    let detail: String
    let actionTitle: String
    var actionSystemImage: String?
    var isEnabled = true
    var isDestructive = false
    var isWorking = false
    var secondaryTitle: String?
    var secondaryAction: (() -> Void)?
    var help: String?
    /// Names the action and its count for VoiceOver; nil falls back to the visible title.
    var accessibilityLabel: String?
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: Spacing.s4) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(metric)
                        .font(Typography.metric)
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(detail)
                        .font(Typography.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: Spacing.s3)
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                }
                if let secondaryTitle, let secondaryAction {
                    Button(secondaryTitle, action: secondaryAction)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
                if !isWorking {
                    primaryButton
                }
            }
            .padding(.horizontal, Spacing.s6)
            .padding(.vertical, Spacing.s3)
            .frame(minHeight: Metrics.commandBarMinHeight)
        }
        .background(Theme.paper)
    }

    @ViewBuilder private var primaryButton: some View {
        if isDestructive {
            Button(actionTitle, systemImage: actionSystemImage ?? "trash", action: action)
                .buttonStyle(.borderedProminent)
                .tint(Theme.red)
                .controlSize(.large)
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!isEnabled)
                .help(help ?? actionTitle)
                .accessibilityLabel(accessibilityLabel ?? actionTitle)
        } else {
            if let actionSystemImage {
                Button(actionTitle, systemImage: actionSystemImage, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .controlSize(.large)
                    .disabled(!isEnabled)
                    .help(help ?? actionTitle)
                    .accessibilityLabel(accessibilityLabel ?? actionTitle)
            } else {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .controlSize(.large)
                    .disabled(!isEnabled)
                    .help(help ?? actionTitle)
                    .accessibilityLabel(accessibilityLabel ?? actionTitle)
            }
        }
    }
}
