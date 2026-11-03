import SwiftUI

/// Icon and color for each category. Used by the sidebar, overview and sheets.
struct CategoryStyle {
    let symbol: String
    let color: Color

    static func of(_ id: String) -> CategoryStyle {
        styles[id] ?? CategoryStyle(symbol: "folder", color: .gray)
    }

    static let styles: [String: CategoryStyle] = [
        "overview": CategoryStyle(symbol: "gauge.with.dots.needle.67percent", color: .blue),
        "trash": CategoryStyle(symbol: "trash", color: .gray),
        "caches": CategoryStyle(symbol: "archivebox", color: .orange),
        "logs": CategoryStyle(symbol: "doc.text.magnifyingglass", color: .brown),
        "xcode": CategoryStyle(symbol: "hammer", color: .blue),
        "xcode-archives": CategoryStyle(symbol: "shippingbox", color: .indigo),
        "package-caches": CategoryStyle(symbol: "cube.box", color: .purple),
        "browser": CategoryStyle(symbol: "globe", color: .cyan),
        "mail-downloads": CategoryStyle(symbol: "envelope", color: .blue),
        "installers": CategoryStyle(symbol: "opticaldiscdrive", color: .teal),
        "ios-backups": CategoryStyle(symbol: "iphone", color: .gray),
        "duplicates": CategoryStyle(symbol: "doc.on.doc", color: .pink),
        "large-files": CategoryStyle(symbol: "externaldrive", color: .red),
        "leftovers": CategoryStyle(symbol: "puzzlepiece.extension", color: .mint),
        "similar-photos": CategoryStyle(symbol: "photo.on.rectangle", color: .green),
        "blurry-photos": CategoryStyle(symbol: "camera.metering.unknown", color: .yellow),
        "similar-videos": CategoryStyle(symbol: "film.stack", color: .green),
        "snapshots": CategoryStyle(symbol: "clock.arrow.circlepath", color: .gray),
        "disk-map": CategoryStyle(symbol: "square.grid.3x3.fill", color: .blue),
    ]
}
