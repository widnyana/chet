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
    var isSecondaryEnabled = true
    var help: String?
    /// Names the action and its count for VoiceOver; nil falls back to the visible title.
    var accessibilityLabel: String?
    /// Why the primary is disabled. Shown only while it is disabled.
    var disabledReason: String?
    var primaryIdentifier: String?
    var secondaryIdentifier: String?
    let action: () -> Void

    var body: some View {
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
            if !isEnabled || isWorking, let disabledReason {
                Text(disabledReason)
                    .font(Typography.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
            }
            if isWorking {
                ActivitySpinner()
            }
            if let secondaryTitle, let secondaryAction {
                SecondaryActionButton(
                    title: secondaryTitle, isEnabled: isSecondaryEnabled,
                    action: secondaryAction
                )
                .modifier(OptionalAccessibilityIdentifier(identifier: secondaryIdentifier))
            }
            primaryButton
                .modifier(OptionalAccessibilityIdentifier(identifier: primaryIdentifier))
        }
        .pageHorizontalPadding()
        .padding(.vertical, Spacing.s3)
        .frame(minHeight: Metrics.commandBarMinHeight)
    }

    @ViewBuilder private var primaryButton: some View {
        if isDestructive {
            DestructiveActionButton(
                title: actionTitle,
                systemImage: actionSystemImage ?? "trash",
                isEnabled: isEnabled && !isWorking,
                help: help,
                accessibilityLabel: accessibilityLabel,
                shortcut: .delete,
                shortcutModifiers: .command,
                action: action)
        } else {
            PrimaryActionButton(
                title: actionTitle,
                systemImage: actionSystemImage,
                isEnabled: isEnabled && !isWorking,
                help: help,
                accessibilityLabel: accessibilityLabel,
                action: action)
        }
    }
}
