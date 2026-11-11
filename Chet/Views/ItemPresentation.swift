import AppKit
import ChetCore
import SwiftUI

/// Caches workspace icons by path so row renders stay cheap.
@MainActor
enum IconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(for url: URL) -> NSImage {
        if let image = cache[url.path] { return image }
        if cache.count > 512 { cache.removeAll() }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache[url.path] = image
        return image
    }
}

/// App name and icon for a bundle ID. Cached: Launch Services lookups touch the disk.
@MainActor
enum AppInfo {
    private static var cache: [String: (name: String, icon: NSImage)?] = [:]

    static func lookup(_ bundleID: String) -> (name: String, icon: NSImage)? {
        if let hit = cache[bundleID] { return hit }
        var found: (name: String, icon: NSImage)?
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let name = FileManager.default.displayName(atPath: app.path)
            found = (
                name.hasSuffix(".app") ? String(name.dropLast(4)) : name, NSWorkspace.shared.icon(forFile: app.path)
            )
        }
        cache[bundleID] = .some(found)
        return found
    }
}

/// Name cell: app or file icon, a readable title, and a second line saying which app and folder it belongs to.
struct ItemNameCell: View {
    let item: ScanItem

    var body: some View {
        let app = DisplayName.sourceBundleID(for: item.url, owner: item.ownerBundleID).flatMap(AppInfo.lookup)
        let titledByApp = item.ownerBundleID == nil && app != nil
        let bundleName =
            item.ownerBundleID == nil && app == nil
            ? DisplayName.sourceBundleID(for: item.url, owner: item.ownerBundleID)
            : nil
        let split = bundleName.flatMap { DisplayName.bundleIDParts($0) }
        let location = DisplayName.location(of: item.url)
        let subtitle = item.kind.map { "\($0) · \(location)" } ?? location
        HStack(spacing: Spacing.s2) {
            Image(nsImage: app?.icon ?? IconCache.icon(for: item.url))
                .resizable()
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(
                    titledByApp
                        ? (app?.name ?? "")
                        : (split.map { $0.title } ?? DisplayName.title(for: item.url))
                )
                .font(Typography.row)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                Text(subtitle)
                    .font(Typography.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .help(item.url.path)
        .accessibilityElement(children: .combine)
    }
}
