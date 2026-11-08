import MackitCore
import SwiftUI
@preconcurrency import UserNotifications

/// Toolbar status: while scanning, a progress ring, the current step, found bytes and Stop;
/// when idle, the Scan button.
struct ScanStatusView: View {
    @Environment(ScanModel.self) private var model

    var body: some View {
        if model.isScanning {
            // One quiet state, not a sentence: a ring with the coarse scan fraction and
            // its percent centered. The words live in the tooltip and the disk map's
            // progress strip, never in the toolbar. Clicking pauses or resumes.
            Button {
                model.togglePause()
            } label: {
                ZStack {
                    Circle()
                        .stroke(.quaternary, lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: progressFraction)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    if model.isPaused {
                        // Percent and glyph cannot share 26 pt; pausing swaps them.
                        Image(systemName: "pause.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(Int((progressFraction * 100).rounded()))%")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                    }
                }
                .frame(width: 26, height: 26)
                .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isPaused ? "Resume scan" : "Pause scan")
            .help(phaseDescription)
        } else {
            Button(model.lastScan == nil ? "Scan" : "Scan Again", systemImage: "magnifyingglass") {
                model.scan()
            }
            .buttonStyle(.glassProminent)
            .help("Scan this Mac for junk (Command-R)")
        }
    }

    /// Coarse scan-stage fraction: completed steps over the five scan steps. Exact
    /// counts (6 of 27 roots) exist only on the disk map page; the toolbar stays
    /// page-independent.
    private var progressFraction: Double {
        let total = max(model.steps.count, 1)
        return Double(model.steps.filter(\.done).count) / Double(total)
    }

    /// Tooltip copy: the words the old glass capsule showed, now out of sight.
    private var phaseDescription: String {
        var parts: [String] = []
        if let activity = model.activity {
            parts.append(activity.phase.title)
            if activity.total > 0 { parts.append("\(activity.done) of \(activity.total)") }
        } else {
            parts.append(model.currentStep?.title ?? "Scanning")
        }
        if model.isPaused {
            parts.append("paused at \(Int((progressFraction * 100).rounded())) percent")
        }
        return parts.joined(separator: ", ")
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
