import MackitCore
import SwiftUI
@preconcurrency import UserNotifications

/// Toolbar status: while scanning, a progress ring, the current step, found bytes and Stop;
/// when idle, the Scan button.
struct ScanStatusView: View {
    @Environment(ScanModel.self) private var model

    var body: some View {
        if model.isScanning {
            HStack(spacing: 10) {
                ProgressView(value: Double(model.steps.filter(\.done).count), total: Double(model.steps.count))
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.currentStep?.title ?? "Scanning").font(.callout).lineLimit(1)
                    Group {
                        if let folder = model.rootsProgress?.currentFolder, !folder.isEmpty {
                            Text(folder).lineLimit(1).truncationMode(.middle).help(folder)
                        } else {
                            Text("\(model.totalBytes.formatted(.byteCount(style: .file))) found")
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        if let rate = model.rate {
                            Text(String(format: "%.1fk files/s", rate)).monospacedDigit()
                        }
                        if let started = model.scanStartedAt {
                            Text(Self.elapsed(since: started)).monospacedDigit()
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
                Button("Stop", systemImage: "stop.fill") { model.cancel() }
                    .help("Stop the scan (Command-R)")
            }
        } else {
            Button(model.lastScan == nil ? "Scan" : "Scan Again", systemImage: "magnifyingglass") {
                model.scan()
            }
            .buttonStyle(.glassProminent)
            .help("Scan this Mac for junk (Command-R)")
        }
    }

    static func elapsed(since date: Date) -> String {
        let interval = Int(Date().timeIntervalSince(date))
        return String(format: "%02d:%02d", interval / 60, interval % 60)
    }

    /// Which scan step produces a category; nil for pages that are not categories.
    static func step(forCategory id: String) -> MackitCore.ScanStep {
        switch id {
        case "duplicates": .duplicates
        case "large-files": .largeFiles
        case "leftovers": .leftovers
        case "similar-photos", "blurry-photos": .photos
        case "similar-videos": .videos
        case "snapshots": .snapshots
        case "tagged-caches": .index
        default: .rules
        }
    }
}

/// Toast shown for 4 seconds after a scan finishes; notifies when the app is backgrounded.
struct ScanFinishedToast: View {
    @Environment(ScanModel.self) private var model
    @State private var text: String?

    var body: some View {
        VStack {
            if let text {
                Label(text, systemImage: "checkmark.circle.fill")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: text)
        .onChange(of: model.isScanning) { was, now in
            if was, !now, model.didFinishScan { show() }
        }
    }

    private func show() {
        text = "Scan finished: \(model.totalBytes.formatted(.byteCount(style: .file))) can be cleaned"
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
            content.body = "\(bytes) can be cleaned"
            let request = UNNotificationRequest(identifier: "scan-finished", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }
}
