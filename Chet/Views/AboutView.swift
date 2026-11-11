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
    private let productSentence = "Clean up, fine-tune, and take control of your Mac."
    private let accessSentence = "Some folders stay hidden until you grant access."

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                Hairline()
                    .padding(.vertical, Spacing.s6)
                if let build {
                    facts(build)
                } else {
                    LoadingStateView(message: "Reading this build")
                }
            }
            .pageHorizontalPadding()
            .padding(.vertical, Spacing.s6)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.paper)
        .frame(width: 560, height: 560)
        .task { await load() }
        .onAppear {
            VerboseLog.event(.debug, .ui, .uiViewAppeared, .code(.view, .viewAbout))
        }
        .onChange(of: model.isCleaning) { _, cleaning in
            if !cleaning { refreshPaths() }
        }
    }

    private var hero: some View {
        VStack(spacing: Spacing.s3) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: Metrics.aboutIconSize, height: Metrics.aboutIconSize)
            Text("Chet")
                .font(Typography.title)
                .foregroundStyle(Theme.ink)
            Text(productSentence)
                .font(Typography.body)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: Metrics.aboutIntroWidth)
            if let versionLine {
                Text(versionLine)
                    .font(Typography.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .monospacedDigit()
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(heroLabel)
    }

    private var versionLine: String? {
        guard let build else { return nil }
        return "Version \(build.version ?? "Unknown") (build \(build.build ?? "Unknown"))"
    }

    private var heroLabel: String {
        guard let versionLine else { return "Chet, \(productSentence)" }
        return "Chet, \(productSentence), \(versionLine)"
    }

    private func facts(_ build: BuildInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            AboutRow(label: "Minimum macOS") {
                valueText(build.minimumOS ?? "Unknown")
            }
            AboutRow(label: "Built") {
                valueText(
                    build.builtDate?.formatted(date: .abbreviated, time: .shortened)
                        ?? build.builtAt ?? "Unknown")
            }
            AboutRow(label: "Commit") {
                valueText(build.shortCommit ?? "Unknown")
                    .monospaced()
            }
            AboutRow(
                label: "Full Disk Access",
                actionTitle: model.access == .granted ? nil : "Open Settings",
                actionHelp: "Open Full Disk Access in System Settings",
                action: model.access == .granted
                    ? nil : { _ = NSWorkspace.shared.open(FullDiskAccess.settingsURL) }
            ) {
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    StatusLabel(
                        text: model.access == .granted ? "Granted" : "Not granted",
                        systemImage: model.access == .granted
                            ? "checkmark.circle" : "exclamationmark.triangle",
                        tone: model.access == .granted ? .neutral : .amber,
                        help: model.access == .granted ? "Full Disk Access is granted" : accessSentence)
                    if model.access != .granted {
                        Text(accessSentence)
                            .font(Typography.caption)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
            }
            AboutRow(label: "Last scan") {
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    valueText(lastScan.value)
                    if let detail = lastScan.detail {
                        Text(detail)
                            .font(Typography.caption)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
            }
            AboutRow(
                label: "Audit log",
                actionTitle: logExists ? "Show" : nil,
                actionHelp: "Open the clean log",
                action: logExists ? { _ = NSWorkspace.shared.open(auditLog.url) } : nil
            ) {
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    pathText(auditLog.url.path)
                    if !logExists {
                        Text("No log yet")
                            .font(Typography.caption)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
            }
            AboutRow(
                label: "Logs folder",
                actionTitle: logsExist ? "Open" : nil,
                actionHelp: "Open ~/Library/Logs/chet",
                action: logsExist ? { _ = NSWorkspace.shared.open(logsDirectory) } : nil
            ) {
                pathText(logsDirectory.path)
            }
        }
    }

    private func valueText(_ text: String) -> some View {
        Text(text)
            .font(Typography.row)
            .monospacedDigit()
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
    }

    private func pathText(_ path: String) -> some View {
        Text(path)
            .font(Typography.caption)
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
            .help(path)
    }

    private var lastScan: (value: String, detail: String?) {
        if model.isScanning { return ("Scanning", nil) }
        guard let date = model.lastScan else { return ("No scan yet", nil) }
        return (
            model.lastScanBytes.formatted(.byteCount(style: .file)),
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

private struct AboutRow<Value: View>: View {
    let label: String
    var actionTitle: String?
    var actionHelp: String?
    var action: (() -> Void)?
    let value: Value

    init(
        label: String, actionTitle: String? = nil, actionHelp: String? = nil,
        action: (() -> Void)? = nil, @ViewBuilder value: () -> Value
    ) {
        self.label = label
        self.actionTitle = actionTitle
        self.actionHelp = actionHelp
        self.action = action
        self.value = value()
    }
    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s3) {
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(Theme.inkSecondary)
                .frame(width: Metrics.aboutLabelWidth, alignment: .leading)
            value
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle, let action {
                SecondaryActionButton(title: actionTitle, help: actionHelp, action: action)
            }
        }
        .frame(minHeight: Metrics.rowHeight)
    }
}
