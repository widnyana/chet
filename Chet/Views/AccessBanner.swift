import AppKit
import ChetCore
import SwiftUI
@preconcurrency import UserNotifications

/// One full-width strip under the toolbar for global states: dry run, limited
/// access, and the scan result. It pushes content down; it never floats over it.
struct TopStatusStrip: View {
    @Environment(ScanModel.self) private var model
    @State private var finishedText: String?

    var body: some View {
        Group {
            if DryRun.enabled {
                strip(
                    icon: "exclamationmark.triangle",
                    text: "Preview only. No files will be moved.",
                    tone: .amber,
                    actionTitle: nil,
                    action: nil,
                    dismiss: nil)
            } else if model.showsAccessBanner {
                accessStrip
            } else if let finishedText {
                strip(
                    icon: "checkmark.circle",
                    text: finishedText,
                    tone: .neutral,
                    actionTitle: nil,
                    action: nil,
                    dismiss: { self.finishedText = nil })
            }
        }
        .modifier(ScanFinishedObserver(text: $finishedText))
    }

    private var accessStrip: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.s3) {
                StatusLabel(
                    text: "Limited access. Some folders are hidden.",
                    systemImage: "lock.shield",
                    tone: .amber)
                Spacer(minLength: Spacing.s3)
                SecondaryActionButton(
                    title: "Open Settings",
                    action: {
                        model.recordGrantAttempt()
                        NSWorkspace.shared.open(FullDiskAccess.settingsURL)
                    })
                IconActionButton(
                    systemImage: "xmark",
                    label: "Hide until the next launch",
                    action: { model.bannerDismissed = true })
            }
            if model.grantAttempts >= 2 {
                Text("Chet may appear more than once in the list. Remove the old entry.")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Hairline()
        }
        .padding(.horizontal, Spacing.s6)
        .padding(.vertical, Spacing.s2)
        .background(Theme.paperRaised)
        .task {
            while !Task.isCancelled && model.showsAccessBanner {
                try? await Task.sleep(for: .seconds(1))
                model.refreshAccess()
            }
        }
    }

    private func strip(
        icon: String,
        text: String,
        tone: StatusTone,
        actionTitle: String?,
        action: (() -> Void)?,
        dismiss: (() -> Void)?
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.s3) {
                StatusLabel(text: text, systemImage: icon, tone: tone)
                Spacer(minLength: Spacing.s3)
                if let actionTitle, let action {
                    SecondaryActionButton(title: actionTitle, action: action)
                }
                if let dismiss {
                    IconActionButton(systemImage: "xmark", label: "Dismiss", action: dismiss)
                }
            }
            .padding(.horizontal, Spacing.s6)
            .padding(.vertical, Spacing.s3)
            .background(Theme.paperRaised)
            Hairline()
        }
    }
}

struct ScanFinishedObserver: ViewModifier {
    @Environment(ScanModel.self) private var model
    @Binding var text: String?

    func body(content: Content) -> some View {
        content
            .onChange(of: model.isScanning) { was, now in
                if was, !now, model.didFinishScan {
                    show()
                }
            }
    }

    private func show() {
        text = "Scan finished. \(model.totalBytes.formatted(.byteCount(style: .file))) can be freed."
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            text = nil
        }
        notifyIfBackgrounded()
    }

    private func notifyIfBackgrounded() {
        guard !NSApp.isActive else { return }
        let bytes = model.totalBytes.formatted(.byteCount(style: .file))
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Scan finished"
            content.body = "\(bytes) can be freed."
            let request = UNNotificationRequest(identifier: "scan-finished", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }
}
