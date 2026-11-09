import SwiftUI

/// The monochrome symbol for a category. Color is not part of category identity.
struct CategoryStyle {
    let symbol: String

    static func of(_ id: String) -> CategoryStyle {
        CategoryStyle(symbol: symbols[id] ?? "folder")
    }

    private static let symbols: [String: String] = [
        "overview": "house",
        "applications": "app.dashed",
        "trash": "trash",
        "caches": "archivebox",
        "logs": "doc.text.magnifyingglass",
        "xcode": "hammer",
        "xcode-archives": "shippingbox",
        "package-caches": "cube.box",
        "browser": "globe",
        "mail-downloads": "envelope",
        "installers": "opticaldiscdrive",
        "ios-backups": "iphone",
        "tagged-caches": "tag",
        "duplicates": "doc.on.doc",
        "large-files": "externaldrive",
        "leftovers": "puzzlepiece.extension",
        "dev-garbage": "wrench.and.screwdriver",
        "user-rules": "folder",
        "similar-photos": "photo.on.rectangle",
        "blurry-photos": "camera.metering.unknown",
        "similar-videos": "film.stack",
        "snapshots": "clock.arrow.circlepath",
        "disk-map": "internaldrive",
        "nix": "shippingbox",
    ]
}
