import AppKit
import SwiftUI

// MARK: - Tokens

enum Theme {
    static let paper = dynamic(
        light: NSColor(srgbRed: 0.965, green: 0.957, blue: 0.937, alpha: 1),
        dark: NSColor(srgbRed: 0.071, green: 0.075, blue: 0.086, alpha: 1))
    static let paperRaised = dynamic(
        light: NSColor(srgbRed: 0.988, green: 0.984, blue: 0.973, alpha: 1),
        dark: NSColor(srgbRed: 0.098, green: 0.106, blue: 0.118, alpha: 1))
    static let ink = dynamic(
        light: NSColor(srgbRed: 0.106, green: 0.110, blue: 0.118, alpha: 1),
        dark: NSColor(srgbRed: 0.949, green: 0.941, blue: 0.918, alpha: 1))
    static let inkSecondary = dynamic(
        light: NSColor(srgbRed: 0.388, green: 0.388, blue: 0.373, alpha: 1),
        dark: NSColor(srgbRed: 0.639, green: 0.631, blue: 0.604, alpha: 1))
    static let inkTertiary = dynamic(
        light: NSColor(srgbRed: 0.545, green: 0.541, blue: 0.514, alpha: 1),
        dark: NSColor(srgbRed: 0.455, green: 0.455, blue: 0.435, alpha: 1))
    static let hairline = dynamic(
        light: NSColor(srgbRed: 0.867, green: 0.851, blue: 0.816, alpha: 1),
        dark: NSColor(srgbRed: 0.173, green: 0.180, blue: 0.196, alpha: 1))
    static let accent = dynamic(
        light: NSColor(srgbRed: 0.141, green: 0.298, blue: 0.604, alpha: 1),
        dark: NSColor(srgbRed: 0.561, green: 0.659, blue: 0.910, alpha: 1))
    static let accentSoft = dynamic(
        light: NSColor(srgbRed: 0.910, green: 0.929, blue: 0.973, alpha: 1),
        dark: NSColor(srgbRed: 0.106, green: 0.141, blue: 0.212, alpha: 1))
    static let onAccent = dynamic(
        light: NSColor.white,
        dark: NSColor(srgbRed: 0.063, green: 0.067, blue: 0.078, alpha: 1))
    static let amber = dynamic(
        light: NSColor(srgbRed: 0.604, green: 0.357, blue: 0.000, alpha: 1),
        dark: NSColor(srgbRed: 0.878, green: 0.643, blue: 0.345, alpha: 1))
    static let red = dynamic(
        light: NSColor(srgbRed: 0.639, green: 0.137, blue: 0.106, alpha: 1),
        dark: NSColor(srgbRed: 0.941, green: 0.541, blue: 0.510, alpha: 1))
    static let capacityUsed = dynamic(
        light: NSColor(srgbRed: 0.839, green: 0.824, blue: 0.784, alpha: 1),
        dark: NSColor(srgbRed: 0.227, green: 0.235, blue: 0.255, alpha: 1))
    static let capacityFree = dynamic(
        light: NSColor(srgbRed: 0.914, green: 0.902, blue: 0.871, alpha: 1),
        dark: NSColor(srgbRed: 0.133, green: 0.141, blue: 0.157, alpha: 1))

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            })
    }
}

enum Typography {
    static let display = Font.system(size: 34, weight: .semibold)
    static let title = Font.system(size: 22, weight: .semibold)
    static let section = Font.system(size: 15, weight: .semibold)
    static let body = Font.system(size: 14, weight: .regular)
    static let row = Font.system(size: 13, weight: .regular)
    static let caption = Font.system(size: 11, weight: .regular)
    static let metric = Font.system(size: 17, weight: .medium)
}

enum Spacing {
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s6: CGFloat = 24
    static let s8: CGFloat = 32
    static let s10: CGFloat = 40
    static let s12: CGFloat = 48
}

enum Metrics {
    static let pageMargin: CGFloat = 24
    static let widePageMargin: CGFloat = 32
    static let contentMaxWidth: CGFloat = 880
    static let rowHeight: CGFloat = 36
    static let commandBarMinHeight: CGFloat = 52
}

// MARK: - Primitives

struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 1)
    }
}

enum StatusTone {
    case neutral, amber, red, accent

    var color: Color {
        switch self {
        case .neutral: Theme.inkSecondary
        case .amber: Theme.amber
        case .red: Theme.red
        case .accent: Theme.accent
        }
    }
}

struct StatusLabel: View {
    let text: String
    let systemImage: String
    var tone: StatusTone = .neutral
    var help: String?

    var body: some View {
        HStack(spacing: Spacing.s1) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
            Text(text)
                .font(Typography.caption)
        }
        .foregroundStyle(tone.color)
        .help(help ?? text)
        .accessibilityElement(children: .combine)
    }
}

struct PageHeader: View {
    let title: String
    var subtitle: String?
    var metric: String?
    var metricLabel: String?
    var icon: NSImage?

    var body: some View {
        VStack(spacing: Spacing.s3) {
            HStack(alignment: .top, spacing: Spacing.s3) {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 44, height: 44)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Typography.title)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(Typography.body)
                            .foregroundStyle(Theme.inkSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: Spacing.s3)
                if let metric {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(metric)
                            .font(Typography.display)
                            .monospacedDigit()
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        if let metricLabel {
                            Text(metricLabel)
                                .font(Typography.caption)
                                .foregroundStyle(Theme.inkSecondary)
                        }
                    }
                }
            }
            Hairline()
        }
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        VStack(spacing: Spacing.s2) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
                Text(title)
                    .font(Typography.section)
                    .foregroundStyle(Theme.ink)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(Typography.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .monospacedDigit()
                }
            }
            Hairline()
        }
    }
}

// MARK: - Selection and action

// MARK: - States

struct EmptyStateView: View {
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text(title)
                .font(Typography.section)
                .foregroundStyle(Theme.ink)
            // No fixedSize(vertical:): measured without a width proposal it reports a
            // huge ideal height, which NavigationSplitView adopts. On the Disk map page
            // that pushed the whole split view past the window and blanked the sidebar.
            Text(message)
                .font(Typography.body)
                .foregroundStyle(Theme.inkSecondary)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .controlSize(.large)
                    .padding(.top, Spacing.s2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.s4)
    }
}

struct LoadingStateView: View {
    let message: String

    var body: some View {
        HStack(spacing: Spacing.s2) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(Typography.body)
                .foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.s4)
    }
}

struct ErrorStateView: View {
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            StatusLabel(text: title, systemImage: "exclamationmark.triangle", tone: .red)
            Text(message)
                .font(Typography.body)
                .foregroundStyle(Theme.inkSecondary)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.s4)
    }
}

// MARK: - Capacity

struct CapacityBarView: View {
    let volumeName: String
    let total: Int64
    let free: Int64
    let reclaimable: Int64

    var body: some View {
        let used = max(0, total - free)
        let junk = min(max(0, reclaimable), used)
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
                Text(volumeName)
                    .font(Typography.section)
                    .foregroundStyle(Theme.ink)
                Spacer()
                if total > 0 {
                    Text(
                        "\(free.formatted(.byteCount(style: .file))) available of \(total.formatted(.byteCount(style: .file)))"
                    )
                    .font(Typography.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.inkSecondary)
                } else {
                    Text("Capacity unavailable")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            if total > 0 {
                GeometryReader { geo in
                    HStack(spacing: 1) {
                        Rectangle()
                            .fill(Theme.capacityUsed)
                            .frame(width: share(used - junk) * geo.size.width)
                        Rectangle()
                            .fill(Theme.accent)
                            .frame(width: share(junk) * geo.size.width)
                        Rectangle()
                            .fill(Theme.capacityFree)
                    }
                }
                .frame(height: 10)
                .overlay {
                    Rectangle().strokeBorder(Theme.hairline, lineWidth: 1)
                }
                HStack(spacing: Spacing.s4) {
                    legend("Used", Theme.capacityUsed, used)
                    if reclaimable > 0 {
                        legend("Can be reclaimed", Theme.accent, reclaimable)
                    }
                    legend("Free", Theme.capacityFree, free)
                }
                .font(Typography.caption)
                .foregroundStyle(Theme.inkSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(volumeName). Used \(used.formatted(.byteCount(style: .file))), reclaimable \(reclaimable.formatted(.byteCount(style: .file))), free \(free.formatted(.byteCount(style: .file)))"
        )
    }

    private func legend(_ title: String, _ color: Color, _ value: Int64) -> some View {
        HStack(spacing: Spacing.s1) {
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: 10, height: 10)
            Text("\(title) \(value.formatted(.byteCount(style: .file)))")
                .monospacedDigit()
        }
    }

    private func share(_ part: Int64) -> CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(Double(max(0, part)) / Double(total))
    }
}

// MARK: - Helpers

extension View {
    func pageSurface() -> some View {
        background(Theme.paper)
    }

    func sheetSurface() -> some View {
        background(Theme.paper)
    }
}
