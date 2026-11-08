import Foundation

/// A data-driven junk category: which folders to look in and how to clean them.
/// Each direct child of an existing root folder becomes one ScanItem (or the root itself, see `wholeRoots`).
public struct Rule: Sendable, Identifiable {
    public let id: String
    /// Rules with the same category are shown together.
    public let category: String
    public let title: String
    /// Folders relative to the home folder.
    public let roots: [String]
    public let risk: Risk
    public let mode: DeleteMode
    /// App that owns this data. Cleaning is skipped while it runs.
    public let owningBundleID: String?
    /// Only children not modified for this long are listed.
    public let minAge: TimeInterval?
    /// Only children with one of these lowercase extensions are listed.
    public let extensions: Set<String>?
    /// Child names never listed.
    public let excluded: Set<String>
    /// Keep the most recently modified child of each root (for example the newest device support files).
    public let keepNewest: Bool
    /// Each root folder becomes one item instead of its children (for tool caches full of hash-named folders).
    public let wholeRoots: Bool
    /// When set, the scanner walks each root recursively (depth-capped) and every directory
    /// whose name is in this set becomes one item: regenerable project build dirs such as
    /// Rust's `target/` or Node's `node_modules/`. A matched dir is never descended into.
    public let recursiveNames: Set<String>?

    public init(
        id: String, category: String? = nil, title: String, roots: [String], risk: Risk, mode: DeleteMode,
        owningBundleID: String? = nil, minAge: TimeInterval? = nil, extensions: Set<String>? = nil,
        excluded: Set<String> = [], keepNewest: Bool = false, wholeRoots: Bool = false,
        recursiveNames: Set<String>? = nil
    ) {
        self.id = id
        self.category = category ?? id
        self.title = title
        self.roots = roots
        self.risk = risk
        self.mode = mode
        self.owningBundleID = owningBundleID
        self.minAge = minAge
        self.extensions = extensions
        self.excluded = excluded
        self.keepNewest = keepNewest
        self.wholeRoots = wholeRoots
        self.recursiveNames = recursiveNames
    }
}

extension Rule {
    static let day: TimeInterval = 86_400

    public static let catalog: [Rule] = [
        Rule(id: "trash", title: "Trash", roots: [".Trash"], risk: .safe, mode: .permanent),
        Rule(
            id: "caches", title: "User caches", roots: ["Library/Caches"], risk: .safe, mode: .permanent,
            excluded: ["com.apple.bird", "CloudKit", "com.apple.akd", "id.web.widnyana.mackit"]),
        Rule(
            id: "logs", title: "Logs and crash reports", roots: ["Library/Logs"], risk: .safe, mode: .permanent,
            excluded: ["Mackit", "DiagnosticReports"]),
        Rule(
            id: "xcode", title: "Xcode build data",
            roots: ["Library/Developer/Xcode/DerivedData", "Library/Developer/CoreSimulator/Caches"],
            risk: .safe, mode: .permanent, owningBundleID: "com.apple.dt.Xcode"),
        Rule(
            id: "xcode-device-support", category: "xcode", title: "Old device support files",
            roots: ["Library/Developer/Xcode/iOS DeviceSupport", "Library/Developer/Xcode/watchOS DeviceSupport"],
            risk: .safe, mode: .permanent, owningBundleID: "com.apple.dt.Xcode", keepNewest: true),
        Rule(
            id: "xcode-archives", title: "Xcode archives", roots: ["Library/Developer/Xcode/Archives"],
            risk: .review, mode: .trash),
        Rule(
            id: "package-caches", title: "Package manager caches",
            roots: [
                "Library/Caches/Homebrew", "Library/Caches/pip", "Library/Caches/org.swift.swiftpm",
                "Library/Caches/CocoaPods", "Library/Caches/go-build", "Library/Caches/Yarn", "Library/Caches/pnpm",
                ".npm/_cacache", ".cargo/registry/cache", ".gradle/caches", ".cache/uv",
            ], risk: .safe, mode: .permanent, wholeRoots: true),
        Rule(
            id: "browser-safari", category: "browser", title: "Safari cache",
            roots: ["Library/Caches/com.apple.Safari"], risk: .safe, mode: .permanent,
            owningBundleID: "com.apple.Safari"),
        Rule(
            id: "browser-chrome", category: "browser", title: "Chrome cache", roots: ["Library/Caches/Google/Chrome"],
            risk: .safe, mode: .permanent, owningBundleID: "com.google.Chrome"),
        Rule(
            id: "browser-brave", category: "browser", title: "Brave cache",
            roots: ["Library/Caches/BraveSoftware/Brave-Browser"], risk: .safe, mode: .permanent,
            owningBundleID: "com.brave.Browser"),
        Rule(
            id: "browser-edge", category: "browser", title: "Edge cache", roots: ["Library/Caches/Microsoft Edge"],
            risk: .safe, mode: .permanent, owningBundleID: "com.microsoft.edgemac"),
        Rule(
            id: "browser-firefox", category: "browser", title: "Firefox cache",
            roots: ["Library/Caches/Firefox/Profiles"], risk: .safe, mode: .permanent,
            owningBundleID: "org.mozilla.firefox"),
        Rule(
            id: "browser-arc", category: "browser", title: "Arc cache",
            roots: ["Library/Caches/company.thebrowser.Browser"], risk: .safe, mode: .permanent,
            owningBundleID: "company.thebrowser.Browser"),
        Rule(
            id: "mail-downloads", title: "Mail downloads",
            roots: ["Library/Containers/com.apple.mail/Data/Library/Mail Downloads"], risk: .safe, mode: .permanent,
            owningBundleID: "com.apple.mail"),
        Rule(
            id: "installers", title: "Old installers", roots: ["Downloads"], risk: .review, mode: .trash,
            minAge: 30 * day, extensions: ["dmg", "pkg", "mpkg", "xip", "iso"]),
        Rule(
            id: "ios-backups", title: "iOS device backups", roots: ["Library/Application Support/MobileSync/Backup"],
            risk: .review, mode: .trash),
        Rule(
            id: "dev-garbage", title: "Project build dirs",
            roots: ["Development", "Projects", "Documents", "Desktop"], risk: .review, mode: .trash,
            recursiveNames: ["target", "node_modules", "vendor", ".build", ".gradle", "DerivedData", "Pods"]),
    ]
}
