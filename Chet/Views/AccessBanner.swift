import AppKit
import ChetCore
import SwiftUI
@preconcurrency import UserNotifications

/// One full-width strip under the toolbar for global states: dry run, limited
/// access, and the scan result. It pushes content down; it never floats over it.
struct TopStatusStrip: View {
    @Environment(ScanModel.self) private var model
    /// The page's dry-run gate sentence. Cleaning pages use the default.
    var gateText = "Preview only. Nothing will be removed."
    /// Apps and Homebrew are not scan surfaces, so the finished-scan result never shows there.
    var showsScanResult = true
    @State private var finishedText: String?

    var body: some View {
        Group {
            if DryRun.enabled {
                StatusStrip(
                    text: gateText,
                    systemImage: "exclamationmark.triangle",
                    tone: .amber)
            } else if model.showsAccessBanner {
                accessStrip
            } else if let finishedText, showsScanResult {
                StatusStrip(
                    text: finishedText,
                    systemImage: "checkmark.circle",
                    dismiss: .init(label: "Dismiss", perform: { self.finishedText = nil }))
            }
        }
        .modifier(ScanFinishedObserver(text: $finishedText))
    }

    private var accessStrip: some View {
        VStack(spacing: 0) {
            StatusStrip(
                text: "Limited access. Some folders are hidden.",
                systemImage: "lock.shield",
                tone: .amber,
                action: .init(
                    title: "Open Settings",
                    perform: {
                        model.recordGrantAttempt()
                        NSWorkspace.shared.open(FullDiskAccess.settingsURL)
                    }),
                dismiss: .init(
                    label: "Hide until the next launch",
                    perform: { model.bannerDismissed = true }),
                showsHairline: false)
            if model.grantAttempts >= 2 {
                Text("Chet may be listed twice in Full Disk Access. Remove the old entry.")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .pageHorizontalPadding()
                    .padding(.vertical, Spacing.s2)
            }
            Hairline()
        }
        .task {
            while !Task.isCancelled && model.showsAccessBanner {
                try? await Task.sleep(for: .seconds(1))
                model.refreshAccess()
            }
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
        text = "Scan finished. \(model.totalBytes.formatted(.byteCount(style: .file))) can be reclaimed."
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
            content.body = "\(bytes) can be reclaimed."
            let request = UNNotificationRequest(identifier: "scan-finished", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }
}
