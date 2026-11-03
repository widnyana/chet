import AppKit
import MackitCore
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
        // A cache folder named after a bundle ID: show the app's name instead of the ID.
        let titledByApp = item.ownerBundleID == nil && app != nil
        // Unresolved bundle-ID folder: split "com.apple.HomeKit" -> "HomeKit" + vendor "Apple".
        let bundleName =
            item.ownerBundleID == nil && app == nil
            ? DisplayName.sourceBundleID(for: item.url, owner: item.ownerBundleID)
            : nil
        let split = bundleName.flatMap { DisplayName.bundleIDParts($0) }
        let location = DisplayName.location(of: item.url)
        HStack(spacing: 10) {
            Image(nsImage: app?.icon ?? IconCache.icon(for: item.url.path))
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(
                        titledByApp
                            ? (app?.name ?? "")
                            : (split.map { $0.title } ?? DisplayName.title(for: item.url))
                    )
                    .lineLimit(1)
                    if item.risk == .review { ReviewBadge() }
                }
                Text(
                    item.ownerBundleID != nil && app != nil
                        ? "\(app?.name ?? "") · \(location)"
                        : (split.map { "\($0.vendor) · \(location)" } ?? location)
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            }
        }
        .padding(.vertical, 2)
        .help(item.url.path)
    }
}

struct ReviewBadge: View {
    var body: some View {
        Text("Review")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.orange.opacity(0.15), in: Capsule())
            .help("Check this item before cleaning. It goes to the Trash.")
    }
}
