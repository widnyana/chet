import AppKit
import ChetCore
import SwiftUI

/// The About window: which build is running, the access grant, and where the
/// logs live. Opened from Chet > About Chet.
struct AboutView: View {
    static let windowID = "about"

    @Environment(ScanModel.self) private var model
    @State private var build: BuildInfo?
    @State private var logExists = false
    @State private var logsExist = false

    private let auditLog = AuditLog()
    private var logsDirectory: URL { FlightRecorder.defaultDirectory }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s6) {
                PageHeader(
                    title: "Chet",
                    subtitle: "Finds and removes junk that apps can rebuild, or files you confirm.",
                    metric: build?.version,
                    metricLabel: build?.version == nil ? nil : "version",
                    icon: NSApplication.shared.applicationIconImage)
                if let build {
                    sections(build)
                } else {
                    LoadingStateView(message: "Reading this build")
                }
            }
            .padding(.horizontal, Metrics.widePageMargin)
            .padding(.vertical, Spacing.s6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.paper)
        .frame(width: 560, height: 620)
        .task { await load() }
        .onChange(of: model.isCleaning) { _, cleaning in
            if !cleaning { refreshPaths() }
        }
    }

    private func sections(_ build: BuildInfo) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s8) {
            section("This build") {
                AboutInfoRow(label: "Build", value: build.build ?? "Unknown")
                Hairline()
                AboutInfoRow(label: "Minimum macOS", value: build.minimumOS ?? "Unknown")
            }
            section("Status") {
                AboutInfoRow(
                    label: "Full Disk Access",
                    value: model.access == .granted ? "Granted" : "Not granted",
                    detail: model.access == .granted ? nil : "Some folders stay hidden until you grant it.",
                    tone: model.access == .granted ? .neutral : .amber,
                    systemImage: model.access == .granted ? "checkmark.circle" : "exclamationmark.triangle",
                    actionTitle: model.access == .granted ? nil : "Open Settings",
                    actionHelp: "Open Full Disk Access in System Settings",
                    action: { _ = NSWorkspace.shared.open(FullDiskAccess.settingsURL) })
                Hairline()
                AboutInfoRow(label: "Last scan", value: lastScan.value, detail: lastScan.detail)
            }
            section("Logs") {
                AboutPathRow(
                    label: "Audit log",
                    path: auditLog.url.path,
                    detail: logExists ? "One JSON line per removed item." : "No log yet.",
                    actionTitle: logExists ? "Show" : nil,
                    actionHelp: "Open the clean log",
                    action: { _ = NSWorkspace.shared.open(auditLog.url) })
                Hairline()
                AboutPathRow(
                    label: "Logs folder",
                    path: logsDirectory.path,
                    detail: logsExist ? nil : "The folder appears after the first run.",
                    actionTitle: logsExist ? "Open" : nil,
                    actionHelp: "Open ~/Library/Logs/chet",
                    action: { _ = NSWorkspace.shared.open(logsDirectory) })
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            SectionHeader(title: title)
            VStack(spacing: 0) { content() }
        }
    }

    private var lastScan: (value: String, detail: String?) {
        if model.isScanning {
            return ("Scanning", "Results update when it ends.")
        }
        guard let date = model.lastScan else {
            return ("No scan yet", "Run a scan from the main window.")
        }
        return (
            model.totalBytes.formatted(.byteCount(style: .file)),
            date.formatted(date: .abbreviated, time: .shortened)
        )
    }

    private func load() async {
        guard build == nil else { return }
        build = BuildInfo.current()
        refreshPaths()
    }

    private func refreshPaths() {
        logExists = FileManager.default.fileExists(atPath: auditLog.url.path)
        logsExist = FileManager.default.fileExists(atPath: logsDirectory.path)
    }
}

/// Ledger row for a labelled fact with an optional status icon and action.
private struct AboutInfoRow: View {
    let label: String
    let value: String
    var detail: String?
    var tone: StatusTone = .neutral
    var systemImage: String?
    var actionTitle: String?
    var actionHelp: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: Spacing.s3) {
            Text(label)
                .font(Typography.body)
                .foregroundStyle(Theme.ink)
            Spacer(minLength: Spacing.s3)
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: Spacing.s1) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 11, weight: .medium))
                    }
                    Text(value)
                        .font(Typography.row)
                        .monospacedDigit()
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                .foregroundStyle(tone.color)
                if let detail {
                    Text(detail)
                        .font(Typography.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                }
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(actionHelp ?? actionTitle)
            }
        }
        .padding(.vertical, Spacing.s2)
    }
}

/// Ledger row for a filesystem path, with a secondary action when the path exists.
private struct AboutPathRow: View {
    let label: String
    let path: String
    var detail: String?
    var actionTitle: String?
    var actionHelp: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: Spacing.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(Typography.body)
                    .foregroundStyle(Theme.ink)
                Text(path)
                    .font(Typography.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(path)
                if let detail {
                    Text(detail)
                        .font(Typography.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            Spacer(minLength: Spacing.s3)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(actionHelp ?? actionTitle)
            }
        }
        .padding(.vertical, Spacing.s2)
    }
}
