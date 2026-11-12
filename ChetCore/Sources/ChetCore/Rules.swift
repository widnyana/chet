import Foundation

/// A data-driven junk category: which folders to look in and how to clean them.
/// Each direct child of an existing root folder becomes one ScanItem (or the root itself, see `wholeRoots`).
/// Roots starting with "/" are absolute paths; everything else is relative to the home folder.
public struct Rule: Sendable, Identifiable {
    public let id: String
    /// Rules with the same category are shown together.
    public let category: String
    public let title: String
    /// Relative to home, or absolute when starting with "/".
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
    /// Children emitted as review/Trash instead of the rule's default risk and mode.
    public let reviewNames: Set<String>
    /// Name prefixes of children emitted as review/Trash.
    public let reviewPrefixes: [String]
    /// Take a child's own reverse-DNS name as its owning bundle ID.
    public let childNamesAreBundleIDs: Bool
    /// Keep the most recently modified child of each root (for example the newest device support files).
    public let keepNewest: Bool
    /// Each root folder becomes one item instead of its children (for tool caches full of hash-named folders).
    public let wholeRoots: Bool
    /// When set, the scanner walks each root recursively (depth-capped) and every directory
    /// whose name is in this set becomes one item: regenerable project build dirs such as
    /// Rust's `target/` or Node's `node_modules/`. A matched dir is never descended into.
    public let recursiveNames: Set<String>?
    /// Build artifacts matched by name, sibling, or marker while walking a rule's roots.
    public let recursiveArtifacts: [BuildArtifact]?
    /// Directory names never matched or descended into while walking recursive roots
    /// (`.git` is always skipped). Prevents double-counting under another rule's match.
    public let prunedNames: Set<String>
    /// When true, a walked directory holding a `pyvenv.cfg` child is one item: a Python
    /// virtual environment, whatever it is named (`venv`, `.venv`, `.venv-codegen`).
    public let matchesVirtualEnvironments: Bool
    /// Extra roots discovered from a tool registry at scan time.
    public let discovery: Discovery?
    /// When true, items are listed for size visibility only and the cleaner will never delete them.
    public let listOnly: Bool
    /// Root-owned data: items are shown, and only the privileged helper can remove them.
    public let requiresAdmin: Bool

    /// Root folders that need discovery at scan time instead of a fixed list.
    public enum Discovery: Sendable, Equatable {
        /// One root per VirtualBox machine folder listed in
        /// `~/Library/VirtualBox/VirtualBox.xml`.
        case virtualBoxMachines
        /// The pnpm content-addressable store, when one exists.
        case pnpmStore
    }

    public init(
        id: String, category: String? = nil, title: String, roots: [String], risk: Risk, mode: DeleteMode,
        owningBundleID: String? = nil, minAge: TimeInterval? = nil, extensions: Set<String>? = nil,
        excluded: Set<String> = [], reviewNames: Set<String> = [], reviewPrefixes: [String] = [],
        childNamesAreBundleIDs: Bool = false, keepNewest: Bool = false, wholeRoots: Bool = false,
        recursiveNames: Set<String>? = nil, recursiveArtifacts: [BuildArtifact]? = nil,
        prunedNames: Set<String> = [], discovery: Discovery? = nil,
        listOnly: Bool = false, requiresAdmin: Bool = false, matchesVirtualEnvironments: Bool = false
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
        self.reviewNames = reviewNames
        self.reviewPrefixes = reviewPrefixes
        self.childNamesAreBundleIDs = childNamesAreBundleIDs
        self.keepNewest = keepNewest
        self.wholeRoots = wholeRoots
        self.recursiveNames = recursiveNames
        self.recursiveArtifacts = recursiveArtifacts
        self.prunedNames = prunedNames
        self.matchesVirtualEnvironments = matchesVirtualEnvironments
        self.discovery = discovery
        self.listOnly = listOnly
        self.requiresAdmin = requiresAdmin
    }
}

extension Rule {
    static let day: TimeInterval = 86_400

    public static let catalog: [Rule] = [
        Rule(id: "trash", title: "Trash", roots: [".Trash"], risk: .safe, mode: .permanent),
        Rule(
            id: "caches", title: "User caches", roots: ["Library/Caches"], risk: .safe, mode: .permanent,
            excluded: ["com.apple.bird", "CloudKit", "com.apple.akd", "id.web.widnyana.chet"],
            reviewNames: [
                "com.apple.appstoreagent", "com.apple.CommerceKit.TransactionService", "PassKit", "GameKit",
                "com.apple.ScreenTimeSettingsAgent", "familycircled", "com.apple.Family-Settings.extension",
                "com.apple.appleaccountd", "com.apple.amsaccountsd", "com.apple.storekitagent",
                "com.apple.managedappdistributionagent", "com.apple.amsengagementd", "com.apple.itunescloudd",
                "com.apple.ap.adprivacyd", "com.apple.icloudmailagent",
            ], reviewPrefixes: ["com.apple.ams", "com.apple.storekit"], childNamesAreBundleIDs: true),
        Rule(
            id: "logs", title: "Logs and crash reports", roots: ["Library/Logs"], risk: .safe, mode: .permanent,
            excluded: ["chet", "DiagnosticReports"]),
        Rule(
            id: "logs-crash-reports", category: "logs", title: "Crash reports",
            roots: ["Library/Logs/DiagnosticReports"], risk: .review, mode: .trash),
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
                ".npm/_cacache", ".cargo/registry/cache", ".gradle/caches", ".cache/uv", ".cache/nix",
            ], risk: .safe, mode: .permanent, wholeRoots: true, discovery: .pnpmStore),
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
            id: "browser-vivaldi", category: "browser", title: "Vivaldi cache",
            roots: ["Library/Caches/Vivaldi"], risk: .safe, mode: .permanent,
            owningBundleID: "com.vivaldi.Vivaldi"),
        Rule(
            id: "browser-opera", category: "browser", title: "Opera cache",
            roots: ["Library/Caches/com.operasoftware.Opera"], risk: .safe, mode: .permanent,
            owningBundleID: "com.operasoftware.Opera"),
        Rule(
            id: "browser-chromium", category: "browser", title: "Chromium cache",
            roots: ["Library/Caches/Chromium"], risk: .safe, mode: .permanent,
            owningBundleID: "org.chromium.Chromium"),
        Rule(
            id: "mail-downloads", title: "Mail downloads",
            roots: ["Library/Containers/com.apple.mail/Data/Library/Mail Downloads"], risk: .safe, mode: .permanent,
            owningBundleID: "com.apple.mail"),
        Rule(
            id: "installers", title: "Old installers", roots: ["Downloads", "Desktop"], risk: .review, mode: .trash,
            minAge: 30 * day, extensions: ["dmg", "pkg", "mpkg", "xip", "iso"]),
        Rule(
            id: "ios-backups", title: "iOS device backups", roots: ["Library/Application Support/MobileSync/Backup"],
            risk: .review, mode: .trash),
        Rule(
            id: "dev-garbage", title: "Project build dirs",
            roots: ["Development", "Projects", "Documents", "Desktop"], risk: .review, mode: .trash,
            recursiveArtifacts: BuildArtifact.catalog,
            prunedNames: [".terraform", ".terragrunt-cache"], matchesVirtualEnvironments: true),
        Rule(
            id: "terraform-build-dirs", category: "dev-garbage", title: "Terraform build dirs",
            roots: ["Development", "Projects", "Documents", "Desktop"], risk: .safe, mode: .permanent,
            recursiveNames: [".terraform"],
            prunedNames: DuplicateScope.regenerableNames.union([".terragrunt-cache"])),
        Rule(
            id: "terraform-plugin-cache", category: "dev-garbage", title: "Terraform plugin cache",
            roots: [".terraform.d/plugin-cache"], risk: .safe, mode: .permanent, wholeRoots: true),
        Rule(
            id: "terragrunt-cache", category: "dev-garbage", title: "Terragrunt cache",
            roots: ["Development", "Projects", "Documents", "Desktop"], risk: .review, mode: .trash,
            recursiveNames: [".terragrunt-cache"],
            prunedNames: DuplicateScope.regenerableNames.union([".terraform"])),
        Rule(
            id: "virtualbox-machines", category: "dev-garbage", title: "VirtualBox machines",
            roots: [], risk: .review, mode: .trash, owningBundleID: "org.virtualbox.app.VirtualBox",
            wholeRoots: true, discovery: .virtualBoxMachines),
        Rule(
            id: "nix", title: "Nix",
            roots: ["/nix/store", "/nix/var/nix/profiles"], risk: .informational, mode: .trash,
            wholeRoots: true, listOnly: true),
        Rule(
            id: "system-caches", title: "System caches", roots: ["/Library/Caches"],
            risk: .review, mode: .permanent, requiresAdmin: true),
        Rule(
            id: "system-logs", title: "System logs", roots: ["/Library/Logs"],
            risk: .review, mode: .permanent, requiresAdmin: true),
    ]
}
