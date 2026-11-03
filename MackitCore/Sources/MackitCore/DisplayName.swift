import Foundation

/// Human-readable names for scan items. Pure, so it is unit tested; app names and icons are added by the app.
public enum DisplayName {
    /// Whole-folder tool caches, keyed by path relative to the home folder.
    static let known: [String: String] = [
        "Library/Caches/go-build": "Go build cache",
        "Library/Caches/Homebrew": "Homebrew downloads",
        "Library/Caches/pip": "pip",
        "Library/Caches/org.swift.swiftpm": "Swift Package Manager",
        "Library/Caches/CocoaPods": "CocoaPods",
        "Library/Caches/Yarn": "Yarn",
        "Library/Caches/pnpm": "pnpm",
        ".npm/_cacache": "npm",
        ".cargo/registry/cache": "Cargo registry",
        ".gradle/caches": "Gradle",
        ".cache/uv": "uv",
    ]

    public static func title(for url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        if let rel = relative(url, home), let name = known[rel] { return name }
        let name = url.lastPathComponent
        // Firefox profile folders are "<8 random characters>.<profile name>".
        if url.deletingLastPathComponent().path.hasSuffix("Firefox/Profiles"),
            let dot = name.firstIndex(of: "."), name.distance(from: name.startIndex, to: dot) == 8
        {
            return String(name[name.index(after: dot)...])
        }
        return name
    }

    /// The folder that holds the item, written with `~` for the home folder.
    public static func location(of url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        let parent = url.deletingLastPathComponent()
        guard let rel = relative(parent, home) else { return parent.standardizedFileURL.path }
        return rel.isEmpty ? "~" : "~/" + rel
    }

    /// The app the item belongs to: the rule's owner, else a folder named after a bundle ID.
    public static func sourceBundleID(for url: URL, owner: String?) -> String? {
        owner ?? LeftoverScanner.bundleID(fromName: url.lastPathComponent)
    }

    static func relative(_ url: URL, _ home: URL) -> String? {
        let path = url.standardizedFileURL.path
        let base = home.standardizedFileURL.path
        if path == base { return "" }
        guard path.hasPrefix(base + "/") else { return nil }
        return String(path.dropFirst(base.count + 1))
    }
}
