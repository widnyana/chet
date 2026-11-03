import AppKit
import MackitCore
import SwiftUI

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
        let location = DisplayName.location(of: item.url)
        HStack(spacing: 10) {
            Image(nsImage: app?.icon ?? NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(titledByApp ? (app?.name ?? "") : DisplayName.title(for: item.url))
                        .lineLimit(1)
                    if item.risk == .review { ReviewBadge() }
                }
                Text(item.ownerBundleID != nil && app != nil ? "\(app?.name ?? "") · \(location)" : location)
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

struct RevealButton: View {
    let url: URL

    var body: some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } label: {
            Image(systemName: "magnifyingglass")
        }
        .buttonStyle(.borderless)
        .help("Reveal in Finder")
    }
}
