import AppKit
import CoreServices
import Darwin
import Foundation

/// One row of an application's related data.
public enum AppComponentKind: String, Sendable, Codable, CaseIterable {
    case application, applicationSupport, preferences, caches, logs, containers, groupContainers
    case savedApplicationState, cookies, applicationScripts, launchAgents, launchDaemons, webKit, other

    public var title: String {
        switch self {
        case .application: "App bundle"
        case .applicationSupport: "Application Support"
        case .preferences: "Preferences"
        case .caches: "Caches"
        case .logs: "Logs"
        case .containers: "Containers"
        case .groupContainers: "Group Containers"
        case .savedApplicationState: "Saved Application State"
        case .cookies: "Cookies"
        case .applicationScripts: "Application Scripts"
        case .launchAgents: "Launch Agents"
        case .launchDaemons: "Launch Daemons"
        case .webKit: "WebKit"
        case .other: "Other"
        }
    }
}

/// How strongly a path is tied to the selected app. Only `exclusive` is preselected.
public enum AppOwnership: String, Sendable, Codable {
    case exclusive, probable, shared, privileged, systemProtected

    public var title: String {
        switch self {
        case .exclusive: "Exact match"
        case .probable: "Name match"
        case .shared: "Shared"
        case .privileged: "Needs administrator"
        case .systemProtected: "Protected"
        }
    }
}

/// Why a path matched the app.
public enum AppMatch: String, Sendable, Codable {
    case bundleID, helperBundleID, launchAgent, groupContainer, name, nestedName, unknown
}

public enum AppConfidence: String, Sendable, Codable {
    case high, medium, low
}

/// Other apps' bundle ids with every proper dot-prefix precomputed, so "is this identifier the
/// same as, a parent of, or a child of another app's id" costs O(dots) instead of O(apps).
struct BundleIDIndex: ExpressibleByArrayLiteral, Sendable {
    let ids: Set<String>
    private let parents: Set<String>

    init(_ ids: Set<String>) {
        self.ids = ids
        var parents = Set<String>()
        for id in ids {
            var parts = id.split(separator: ".")
            while parts.count > 1 {
                parts.removeLast()
                parents.insert(parts.joined(separator: "."))
            }
        }
        self.parents = parents
    }

    init(arrayLiteral elements: String...) { self.init(Set(elements)) }

    func isShared(_ identifier: String) -> Bool {
        if ids.contains(identifier) || parents.contains(identifier) { return true }
        var parts = identifier.split(separator: ".")
        while parts.count > 1 {
            parts.removeLast()
            if ids.contains(parts.joined(separator: ".")) { return true }
        }
        return false
    }
}

/// One installed application bundle. Sizes are measured on demand, never at discovery.
public struct InstalledApp: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let name: String
    public let bundleID: String?
    public let version: String?
    public let helperBundleIDs: [String]
    public let vendorLabel: String?
    public let isWritable: Bool
    public let stamp: FileStamp

    public var allBundleIDs: [String] {
        ([bundleID].compactMap { $0 } + helperBundleIDs).reduce(into: [String]()) { ids, id in
            if !ids.contains(id) { ids.append(id) }
        }
    }
}

/// One search location and how deep it may descend. Product-owned folders such as
/// `Library/Application Support/Google/Chrome` are found by descending through the vendor
/// folder, never by deleting the vendor folder.
public struct AppSearchRoot: Hashable, Sendable {
    public let url: URL
    public let kind: AppComponentKind
    public let maxDepth: Int
    public let requiresAdmin: Bool

    public init(url: URL, kind: AppComponentKind, maxDepth: Int, requiresAdmin: Bool = false) {
        self.url = url
        self.kind = kind
        self.maxDepth = maxDepth
        self.requiresAdmin = requiresAdmin
    }
}

/// One related file or folder, with the evidence and safety verdict that produced it.
public struct AppComponent: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let kind: AppComponentKind
    public let ownership: AppOwnership
    public let match: AppMatch
    public let confidence: AppConfidence
    public let bytes: Int64
    public let stamp: FileStamp
    public let requiresAdmin: Bool

    /// Only exact matches are selected for the user. A name guess is never destructive by default.
    public var defaultSelected: Bool { ownership == .exclusive && !requiresAdmin }

    /// Exact and probable matches may be chosen after review. Shared and protected data can
    /// never be moved by this feature; a privileged row needs the registered helper.
    public var isSelectable: Bool {
        (ownership == .exclusive || ownership == .probable) && !requiresAdmin
    }
}

public enum UninstallSkipReason: String, Sendable, Codable, Equatable {
    case missing, changed, policy, appRunning, requiresAdmin, shared, protected, appMissing, notSelected
    case cancelled

    public var title: String {
        switch self {
        case .missing: "Already gone"
        case .changed: "Changed since the preview"
        case .policy: "Protected location"
        case .appRunning: "Its app is running"
        case .requiresAdmin: "Needs administrator rights"
        case .shared: "Shared with another app"
        case .protected: "Protected location"
        case .appMissing: "The app bundle is gone"
        case .notSelected: "Kept"
        case .cancelled: "Cancelled"
        }
    }
}

public enum UninstallOutcome: Sendable, Equatable {
    case trashed(Int64)
    case removed(Int64)
    case skipped(UninstallSkipReason)
    case failed(String)

    public var logValue: String {
        switch self {
        case .trashed: "trashed"
        case .removed: "removed"
        case .skipped(let reason): "skipped:\(reason.rawValue)"
        case .failed(let message): "failed:\(message)"
        }
    }

    var isPermanentRemoval: Bool {
        if case .removed = self { return true }
        return false
    }
}

public struct UninstallResult: Identifiable, Sendable {
    public var id: String { "\(kind.rawValue):\(url.path)" }
    public let url: URL
    public let name: String
    public let kind: AppComponentKind
    public let bytes: Int64
    public let outcome: UninstallOutcome
    public let dryRun: Bool
}

public struct UninstallReport: Sendable {
    public var results: [UninstallResult] = []
    public let dryRun: Bool

    public var trashedBytes: Int64 {
        results.reduce(0) { total, row in
            if case .trashed(let bytes) = row.outcome { return total + bytes }
            return total
        }
    }

    public var trashedCount: Int {
        results.filter { if case .trashed = $0.outcome { return true } else { return false } }.count
    }

    /// Bytes the privileged helper removed for good; never counted as trashed.
    public var removedBytes: Int64 {
        results.reduce(0) { total, row in
            if case .removed(let bytes) = row.outcome { return total + bytes }
            return total
        }
    }

    public var removedCount: Int {
        results.filter { if case .removed = $0.outcome { return true } else { return false } }.count
    }
}

/// What the user confirmed: the app bundle plus the related components they kept selected.
public struct UninstallPlan: Sendable {
    public let app: InstalledApp
    public let components: [AppComponent]
    public let includeApp: Bool
    public let appBytes: Int64
    /// Bundle IDs of the other installed apps, captured with the component scan. Sharing
    /// is rechecked against this snapshot right before a move.
    public let otherBundleIDs: Set<String>
    public let otherNames: Set<String>

    public init(
        app: InstalledApp, components: [AppComponent], includeApp: Bool, appBytes: Int64 = 0,
        otherBundleIDs: Set<String> = [], otherNames: Set<String> = []
    ) {
        self.app = app
        self.components = components
        self.includeApp = includeApp
        self.appBytes = appBytes
        self.otherBundleIDs = otherBundleIDs
        self.otherNames = otherNames
    }
}

/// Discovers app bundles, finds their Library data, and moves confirmed items to the Trash.
/// The app bundle is a separate allow-listed operation because `SafetyPolicy` correctly
/// refuses every `.app` path and every path outside the home folder.
public struct AppUninstaller: Sendable {
    public let home: URL
    public let appFolders: [URL]
    public let searchRoots: [AppSearchRoot]
    public let policy: SafetyPolicy
    public let log: AuditLog?
    public let recorder: FlightRecorder?
    public var isRunning: @Sendable ([String]) -> Bool
    public var trash: @Sendable (URL) throws -> Void
    /// Root-owned remnants. Set only when the helper is registered and the dry-run gate is off;
    /// without it an admin remnant is a skip, and the app bundle is never routed here.
    public let privileged: (@Sendable (URL, String) -> UninstallOutcome?)?

    /// Names that must never drive a name match: they are shared folders, not app names.
    static let genericNames: Set<String> = [
        "app", "application support", "applications", "cache", "caches", "client", "common", "containers",
        "contents", "current", "data", "default", "desktop", "documents", "downloads", "frameworks", "free",
        "helper", "library", "logs", "preferences", "pro", "resources", "saved application state", "server",
        "shared", "support", "system", "user data", "webkit", "x",
    ]

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        appFolders: [URL]? = nil,
        searchRoots: [AppSearchRoot]? = nil,
        policy: SafetyPolicy? = nil,
        log: AuditLog? = nil,
        recorder: FlightRecorder? = nil,
        isRunning: @escaping @Sendable ([String]) -> Bool = { ids in
            ids.contains { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }
        },
        trash: @escaping @Sendable (URL) throws -> Void = { url in
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        },
        privileged: (@Sendable (URL, String) -> UninstallOutcome?)? = nil
    ) {
        self.home = home
        self.appFolders = appFolders ?? Self.defaultAppFolders(home: home)
        self.searchRoots = searchRoots ?? Self.defaultSearchRoots(home: home)
        self.policy = policy ?? SafetyPolicy(home: home)
        self.log = log
        self.recorder = recorder
        self.isRunning = isRunning
        self.trash = trash
        self.privileged = privileged
    }

    public static func defaultAppFolders(home: URL) -> [URL] {
        [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
    }

    /// Home locations plus the system-wide locations the pseudocode listed. System-wide
    /// entries are shown with `.privileged` ownership and can never be selected.
    public static func defaultSearchRoots(home: URL) -> [AppSearchRoot] {
        var roots: [AppSearchRoot] = [
            AppSearchRoot(
                url: home.appendingPathComponent("Library/Application Support"),
                kind: .applicationSupport, maxDepth: 2),
            AppSearchRoot(url: home.appendingPathComponent("Library/Preferences"), kind: .preferences, maxDepth: 0),
            AppSearchRoot(
                url: home.appendingPathComponent("Library/Preferences/ByHost"), kind: .preferences, maxDepth: 0),
            AppSearchRoot(url: home.appendingPathComponent("Library/Caches"), kind: .caches, maxDepth: 1),
            AppSearchRoot(url: home.appendingPathComponent("Library/Logs"), kind: .logs, maxDepth: 1),
            AppSearchRoot(url: home.appendingPathComponent("Library/Containers"), kind: .containers, maxDepth: 0),
            AppSearchRoot(
                url: home.appendingPathComponent("Library/Group Containers"), kind: .groupContainers, maxDepth: 0),
            AppSearchRoot(
                url: home.appendingPathComponent("Library/Saved Application State"),
                kind: .savedApplicationState, maxDepth: 0),
            AppSearchRoot(url: home.appendingPathComponent("Library/Cookies"), kind: .cookies, maxDepth: 0),
            AppSearchRoot(
                url: home.appendingPathComponent("Library/Application Scripts"),
                kind: .applicationScripts, maxDepth: 0),
            AppSearchRoot(url: home.appendingPathComponent("Library/LaunchAgents"), kind: .launchAgents, maxDepth: 0),
            AppSearchRoot(url: home.appendingPathComponent("Library/WebKit"), kind: .webKit, maxDepth: 0),
        ]
        roots += [
            AppSearchRoot(
                url: URL(fileURLWithPath: "/Library/Application Support"), kind: .applicationSupport,
                maxDepth: 2, requiresAdmin: true),
            AppSearchRoot(
                url: URL(fileURLWithPath: "/Library/Preferences"), kind: .preferences, maxDepth: 0,
                requiresAdmin: true),
            AppSearchRoot(
                url: URL(fileURLWithPath: "/Library/LaunchAgents"), kind: .launchAgents, maxDepth: 0,
                requiresAdmin: true),
            AppSearchRoot(
                url: URL(fileURLWithPath: "/Library/LaunchDaemons"), kind: .launchDaemons, maxDepth: 0,
                requiresAdmin: true),
        ]
        return roots
    }

    // MARK: - Discovery

    /// The inventory plus the app folders that could not be read.
    public struct AppInventory: Sendable {
        public let apps: [InstalledApp]
        public let unreadableFolders: [URL]

        public init(apps: [InstalledApp], unreadableFolders: [URL]) {
            self.apps = apps
            self.unreadableFolders = unreadableFolders
        }
    }

    /// App bundles in the configured folders, including one level of subfolders such as
    /// `/Applications/Utilities`. Symlinks are skipped; duplicate bundle IDs keep the first
    /// folder in priority order (`/Applications` before `~/Applications`).
    public func installedApps() -> [InstalledApp] {
        inventory().apps
    }

    public func inventory() -> AppInventory {
        var seenIDs = Set<String>()
        var seenPaths = Set<URL>()
        var apps: [InstalledApp] = []
        var unreadableFolders: [URL] = []
        for folder in appFolders {
            let scan = Self.appBundles(in: folder)
            if !scan.readable {
                unreadableFolders.append(folder)
            }
            for url in scan.urls {
                guard seenPaths.insert(URL(fileURLWithPath: Self.canonicalPath(url))).inserted else { continue }
                guard let app = Self.readApp(url) else { continue }
                let key = app.bundleID ?? app.url.path
                guard seenIDs.insert(key).inserted else { continue }
                apps.append(app)
            }
        }
        return AppInventory(
            apps: apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
            unreadableFolders: unreadableFolders)
    }

    static func appBundles(in folder: URL, depth: Int = 0) -> (urls: [URL], readable: Bool) {
        guard depth <= 1 else { return ([], true) }
        let children: [URL]
        do {
            children = try FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles])
        } catch {
            return ([], false)
        }
        var bundles: [URL] = []
        var readable = true
        for child in children {
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isSymbolicLink != true else { continue }
            if child.pathExtension == "app" {
                bundles.append(child.standardizedFileURL)
            } else if values?.isDirectory == true {
                let nested = appBundles(in: child, depth: depth + 1)
                bundles += nested.urls
                readable = readable && nested.readable
            }
        }
        return (
            bundles.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending },
            readable
        )
    }

    static func readApp(_ url: URL) -> InstalledApp? {
        guard let info = plist(url.appendingPathComponent("Contents/Info.plist")) else { return nil }
        guard let stamp = FileStamp.read(url) else { return nil }
        let bundleID = info["CFBundleIdentifier"] as? String
        let name =
            (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let version = info["CFBundleShortVersionString"] as? String
        let helperIDs = helperBundleIDs(in: url, mainID: bundleID)
        return InstalledApp(
            url: url, name: name, bundleID: bundleID, version: version, helperBundleIDs: helperIDs,
            vendorLabel: bundleID.flatMap(vendorLabel), isWritable: isWritable(url.deletingLastPathComponent()),
            stamp: stamp)
    }

    /// Spotlight's last-used date for a bundle. Nil when the index has no record (never
    /// launched, indexing off). Read on demand, never during discovery.
    public static func lastUsedDate(_ url: URL) -> Date? {
        guard let item = MDItemCreate(nil, url.path as CFString) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    /// Bundle IDs of embedded helpers. They make Chrome Helper data match Chrome without a
    /// vendor wildcard, and they make the running-app guard cover helpers too.
    static func helperBundleIDs(in app: URL, mainID: String?) -> [String] {
        let contents = app.appendingPathComponent("Contents")
        let roots = [
            "Frameworks", "Library/LoginItems", "PlugIns", "XPCServices", "Library/SystemExtensions",
            "Library/LaunchServices",
        ]
        var ids = Set<String>()
        var visited = 0
        for root in roots {
            let start = contents.appendingPathComponent(root)
            guard
                let enumerator = FileManager.default.enumerator(
                    at: start, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles], errorHandler: { _, _ in true })
            else { continue }
            for case let child as URL in enumerator {
                visited += 1
                if visited > 512 { break }
                let values = try? child.resourceValues(forKeys: [.isSymbolicLinkKey])
                guard values?.isSymbolicLink != true else { continue }
                let ext = child.pathExtension.lowercased()
                guard ext == "app" || ext == "appex" || ext == "xpc" else { continue }
                if let id = plist(child.appendingPathComponent("Contents/Info.plist"))?["CFBundleIdentifier"]
                    as? String, id != mainID
                {
                    ids.insert(id)
                }
                enumerator.skipDescendants()
            }
        }
        return ids.sorted()
    }

    static func plist(_ url: URL) -> [String: Any]? {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size > 0, size <= 1_000_000, let data = try? Data(contentsOf: url) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil))
            as? [String: Any]
    }

    // MARK: - Related files

    /// Every related component for one app. Sizes run sequentially per component and the
    /// whole scan is cancellable; the caller drops results from a stale generation.
    public func components(for app: InstalledApp, installedApps: [InstalledApp]) async -> [AppComponent] {
        let others = installedApps.filter { $0.url != app.url }
        let otherIDs = BundleIDIndex(Set(others.flatMap(\.allBundleIDs)))
        let otherNames = Set(others.map { $0.name.lowercased() })
        var found: [URL: FoundComponent] = [:]

        for root in searchRoots {
            guard !Task.isCancelled else { return [] }
            guard isDirectory(root.url) else { continue }
            scan(
                root.url, root: root, depth: 0, app: app, otherIDs: otherIDs, otherNames: otherNames,
                into: &found)
        }

        // A matched ancestor makes its matched children redundant and would double-count.
        // Canonicalize each path once, then test every parent prefix against the set: O(k x depth).
        let canonical = found.mapValues { Self.canonicalPath($0.url) }
        let matchedPaths = Set(canonical.values)
        let kept = found.values.filter { candidate in
            guard !Self.isInside(candidate.url, app.url) else { return false }
            var parent = (canonical[candidate.url] ?? "") as NSString
            while parent.length > 1 {
                parent = parent.deletingLastPathComponent as NSString
                if matchedPaths.contains(parent as String) { return false }
            }
            return true
        }

        var components: [AppComponent] = []
        for candidate in kept.sorted(by: Self.componentOrder) {
            guard !Task.isCancelled else { return [] }
            guard let stamp = FileStamp.read(candidate.url), !stamp.isSymlink, !stamp.isDataless else { continue }
            let bytes = await FileIndexBuilder.allocatedSize(of: candidate.url)
            components.append(
                AppComponent(
                    url: candidate.url, kind: candidate.kind, ownership: candidate.ownership,
                    match: candidate.match, confidence: candidate.confidence, bytes: bytes, stamp: stamp,
                    requiresAdmin: candidate.requiresAdmin))
        }
        return components
    }

    struct FoundComponent {
        let url: URL
        let kind: AppComponentKind
        let ownership: AppOwnership
        let match: AppMatch
        let confidence: AppConfidence
        let requiresAdmin: Bool
    }

    private func scan(
        _ folder: URL, root: AppSearchRoot, depth: Int, app: InstalledApp, otherIDs: BundleIDIndex,
        otherNames: Set<String>, into found: inout [URL: FoundComponent]
    ) {
        guard depth <= root.maxDepth else { return }
        let children =
            (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles])) ?? []
        for child in children {
            if Task.isCancelled { return }
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isSymbolicLink != true else { continue }
            let url = child.standardizedFileURL
            if let match = Self.match(
                url, kind: root.kind, depth: depth, app: app, otherIDs: otherIDs, otherNames: otherNames)
            {
                let protected = policy.isProtectedPath(url)
                let writable = Self.isWritable(url.deletingLastPathComponent())
                let ownership: AppOwnership =
                    protected ? .systemProtected : (root.requiresAdmin || !writable ? .privileged : match.ownership)
                let requiresAdmin = root.requiresAdmin || protected || !writable
                found[url] = FoundComponent(
                    url: url, kind: root.kind, ownership: ownership, match: match.match,
                    confidence: match.confidence, requiresAdmin: requiresAdmin)
                continue
            }
            guard values?.isDirectory == true, depth < root.maxDepth,
                Self.shouldDescend(url, app: app)
            else { continue }
            scan(
                url, root: root, depth: depth + 1, app: app, otherIDs: otherIDs, otherNames: otherNames,
                into: &found)
        }
    }

    struct Matched {
        let ownership: AppOwnership
        let match: AppMatch
        let confidence: AppConfidence
    }

    static func match(
        _ url: URL, kind: AppComponentKind, depth: Int, app: InstalledApp, otherIDs: BundleIDIndex,
        otherNames: Set<String>
    ) -> Matched? {
        let name = url.lastPathComponent
        if kind == .launchAgents || kind == .launchDaemons {
            return matchLaunchAgent(url, app: app)
        }

        if let identifier = normalizedIdentifier(name) {
            let ids = app.allBundleIDs
            if kind == .groupContainers {
                guard isGroupContainer(name) else { return nil }
                let related =
                    ids.contains(identifier) || ids.contains(where: { identifier.hasPrefix($0 + ".") })
                    || (app.vendorLabel.map { identifier == $0 || identifier.hasPrefix($0 + ".") } ?? false)
                guard related else { return nil }
                return Matched(ownership: .shared, match: .groupContainer, confidence: .medium)
            }
            if ids.contains(identifier) {
                if isShared(identifier, with: otherIDs) {
                    return Matched(ownership: .shared, match: .bundleID, confidence: .medium)
                }
                return Matched(ownership: .exclusive, match: .bundleID, confidence: .high)
            }
            if ids.contains(where: { identifier.hasPrefix($0 + ".") }) {
                if isShared(identifier, with: otherIDs) {
                    return Matched(ownership: .shared, match: .helperBundleID, confidence: .medium)
                }
                return Matched(ownership: .exclusive, match: .helperBundleID, confidence: .high)
            }
        }
        return matchName(
            name, kind: kind, depth: depth, app: app, otherIDs: otherIDs, otherNames: otherNames)
    }

    static func matchName(
        _ name: String, kind: AppComponentKind, depth: Int, app: InstalledApp,
        otherIDs: BundleIDIndex, otherNames: Set<String>
    ) -> Matched? {
        guard kind == .applicationSupport || kind == .caches || kind == .logs else { return nil }
        let lower = name.lowercased()
        let appName = app.name.lowercased()
        let bundleLeaf = app.bundleID?.split(separator: ".").last.map { String($0).lowercased() }
        let named = lower == appName || lower == bundleLeaf
        guard named, lower.count >= 4, !genericNames.contains(appName), !genericNames.contains(lower),
            !otherNames.contains(lower)
        else { return nil }
        // A vendor folder ("google") is not the app unless the app is actually named that
        // and no other installed app shares the vendor.
        if let vendor = app.vendorLabel, lower == vendor {
            let sharedVendor = otherIDs.ids.contains { Self.vendorLabel($0) == vendor }
            if sharedVendor || appName != vendor { return nil }
        }
        return Matched(
            ownership: .probable, match: depth == 0 ? .name : .nestedName,
            confidence: depth == 0 ? .medium : .low)
    }

    static func matchLaunchAgent(_ url: URL, app: InstalledApp) -> Matched? {
        guard url.pathExtension.lowercased() == "plist" else { return nil }
        let info = plist(url)
        let fileNameID = normalizedIdentifier(url.lastPathComponent)
        let label = info?["Label"] as? String
        let associated = info?["AssociatedBundleIdentifiers"] as? [String] ?? []
        let program = info?["Program"] as? String
        let arguments = info?["ProgramArguments"] as? [String] ?? []
        let ids = app.allBundleIDs
        func related(_ identifier: String) -> Bool {
            ids.contains(identifier) || ids.contains(where: { identifier.hasPrefix($0 + ".") })
        }
        let matchesLabel = ([fileNameID, label].compactMap { $0 }).contains(where: related)
        let matchesAssociated = associated.contains(where: related)
        let matchesProgram = ([program].compactMap { $0 } + arguments).contains {
            $0 == app.url.path || $0.hasPrefix(app.url.path + "/")
        }
        guard matchesLabel || matchesAssociated || matchesProgram else { return nil }
        return Matched(ownership: .exclusive, match: .launchAgent, confidence: .high)
    }

    /// `com.foo.app.plist` -> `com.foo.app`, `group.com.foo.x` -> `com.foo.x`,
    /// `ABCDE12345.com.foo.x` -> `com.foo.x`, `group.ABCDE12345.com.foo.x` -> `com.foo.x`,
    /// `ABCDE12345.group.com.foo.x` -> `com.foo.x`, `groups.com.apple.podcasts` -> `com.apple.podcasts`,
    /// `com.foo.x.<UUID>` -> `com.foo.x`.
    /// Nil when the name does not look like a reverse-DNS identifier with at least 3 parts.
    static func normalizedIdentifier(_ name: String) -> String? {
        var id = name
        for suffix in [".plist", ".savedState", ".binarycookies"] where id.hasSuffix(suffix) {
            id.removeLast(suffix.count)
        }
        var parts = id.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        var changed = true
        while changed {
            changed = false
            if parts.count >= 3,
                parts[0].count == 10, parts[0].allSatisfy({ $0.isUppercase || $0.isNumber })
            {
                parts.removeFirst()
                changed = true
            }
            if let first = parts.first, ["group", "groups", "systemgroup"].contains(first.lowercased()) {
                parts.removeFirst()
                changed = true
            }
        }
        if parts.count >= 4, let last = parts.last, last.count == 36, UUID(uuidString: last) != nil {
            parts.removeLast()
        }
        guard parts.count >= 3,
            parts.allSatisfy({
                !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
            })
        else { return nil }
        return parts.joined(separator: ".")
    }

    static func vendorLabel(_ bundleID: String) -> String? {
        let parts = bundleID.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        return parts[1].lowercased()
    }

    static func isGroupContainer(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasPrefix("group.") || lower.hasPrefix("groups.") || lower.hasPrefix("systemgroup.")
            || lower.contains(".group.") || lower.contains(".groups.") || lower.contains(".systemgroup.")
    }

    static func isShared(_ identifier: String, with otherIDs: BundleIDIndex) -> Bool {
        otherIDs.isShared(identifier)
    }

    static func shouldDescend(_ url: URL, app: InstalledApp) -> Bool {
        let name = url.lastPathComponent.lowercased()
        if name == "chet" { return false }
        if let vendor = app.vendorLabel, name == vendor { return true }
        if name == app.name.lowercased() { return true }
        if let id = app.bundleID?.lowercased() {
            return id.split(separator: ".").dropFirst().contains { $0 == name }
        }
        return false
    }

    static func componentOrder(_ left: FoundComponent, _ right: FoundComponent) -> Bool {
        let order = AppComponentKind.allCases
        let l = order.firstIndex(of: left.kind) ?? order.count
        let r = order.firstIndex(of: right.kind) ?? order.count
        if l != r { return l < r }
        return left.url.path.localizedStandardCompare(right.url.path) == .orderedAscending
    }

    // MARK: - Removal

    /// Moves the confirmed rows to the Trash, components first and the app bundle last. A
    /// root-owned remnant goes through the privileged helper instead and is gone for good.
    /// The app is refused entirely while it or a helper runs. Every row is revalidated.
    public func uninstall(_ plan: UninstallPlan, dryRun: Bool) async -> UninstallReport {
        var report = UninstallReport(dryRun: dryRun)
        let appRunning = isRunning(plan.app.allBundleIDs)
        let otherIDs = BundleIDIndex(plan.otherBundleIDs)
        let otherNames = plan.otherNames

        if appRunning {
            for component in plan.components {
                report.results.append(
                    result(for: component, outcome: .skipped(.appRunning), dryRun: dryRun))
            }
            report.results.append(appResult(plan, outcome: .skipped(.appRunning), dryRun: dryRun))
            logReport(report)
            return report
        }

        for component in plan.components {
            if Task.isCancelled { break }
            let reason = revalidate(
                component, app: plan.app, otherIDs: otherIDs, otherNames: otherNames)
            if let reason {
                report.results.append(
                    result(for: component, outcome: .skipped(reason), dryRun: dryRun))
                continue
            }
            if component.requiresAdmin {
                if dryRun {
                    report.results.append(
                        result(for: component, outcome: .removed(component.bytes), dryRun: true))
                } else if let privileged {
                    let outcome =
                        privileged(component.url, plan.app.bundleID ?? "") ?? .skipped(.requiresAdmin)
                    // The report always carries the size measured for the row; the helper only
                    // says whether the removal happened.
                    report.results.append(
                        result(
                            for: component,
                            outcome: outcome.isPermanentRemoval ? .removed(component.bytes) : outcome,
                            dryRun: false))
                } else {
                    report.results.append(
                        result(for: component, outcome: .skipped(.requiresAdmin), dryRun: false))
                }
                continue
            }
            if dryRun {
                report.results.append(
                    result(for: component, outcome: .trashed(component.bytes), dryRun: true))
                continue
            }
            do {
                try trash(component.url)
                report.results.append(
                    result(for: component, outcome: .trashed(component.bytes), dryRun: false))
            } catch {
                report.results.append(
                    result(for: component, outcome: .failed(error.localizedDescription), dryRun: false))
            }
        }

        if Task.isCancelled {
            if plan.includeApp {
                report.results.append(appResult(plan, outcome: .skipped(.cancelled), dryRun: dryRun))
            }
            logReport(report)
            return report
        }

        if plan.includeApp {
            if isRunning(plan.app.allBundleIDs) {
                report.results.append(appResult(plan, outcome: .skipped(.appRunning), dryRun: dryRun))
            } else if let reason = appRevalidation(plan.app) {
                report.results.append(appResult(plan, outcome: .skipped(reason), dryRun: dryRun))
            } else if dryRun {
                report.results.append(appResult(plan, outcome: .trashed(plan.appBytes), dryRun: true))
            } else {
                do {
                    try trash(plan.app.url)
                    report.results.append(appResult(plan, outcome: .trashed(plan.appBytes), dryRun: false))
                } catch {
                    report.results.append(
                        appResult(plan, outcome: .failed(error.localizedDescription), dryRun: false))
                }
            }
        } else {
            report.results.append(appResult(plan, outcome: .skipped(.notSelected), dryRun: dryRun))
        }

        logReport(report)
        if let recorder {
            let removed = report.removedCount > 0 ? ", \(report.removedCount) removed" : ""
            recorder.record(
                step: "uninstall",
                "\(report.trashedCount) trashed, \(report.trashedBytes) bytes\(removed)\(dryRun ? ", dry run" : "")")
        }
        return report
    }

    private func revalidate(
        _ component: AppComponent, app: InstalledApp, otherIDs: BundleIDIndex, otherNames: Set<String>
    ) -> UninstallSkipReason? {
        guard let current = FileStamp.read(component.url) else { return .missing }
        guard !current.isSymlink, current == component.stamp else { return .changed }
        guard !policy.isProtectedPath(component.url) else { return .protected }
        // A root-owned remnant may go through the helper. Shared data and macOS-protected
        // paths stay refused: the helper is not a licence to take another app's files.
        if component.ownership == .shared { return .shared }
        guard component.isSelectable || component.ownership == .privileged else { return .protected }
        if Self.isInside(component.url, home) {
            guard policy.isDeletable(component.url) == .allowed else { return .policy }
        }
        guard
            Self.match(
                component.url, kind: component.kind, depth: 0, app: app, otherIDs: otherIDs,
                otherNames: otherNames) != nil
        else { return .changed }
        return nil
    }

    private func appRevalidation(_ app: InstalledApp) -> UninstallSkipReason? {
        guard let current = FileStamp.read(app.url) else { return .appMissing }
        guard !current.isSymlink, current == app.stamp else { return .changed }
        guard let currentApp = Self.readApp(app.url), currentApp.bundleID == app.bundleID else {
            return .changed
        }
        guard !policy.isProtectedPath(app.url) else { return .protected }
        guard appFolders.contains(where: { Self.isInside(app.url, $0) }) else { return .policy }
        guard Self.isWritable(app.url.deletingLastPathComponent()) else { return .requiresAdmin }
        return nil
    }

    private func result(for component: AppComponent, outcome: UninstallOutcome, dryRun: Bool) -> UninstallResult {
        UninstallResult(
            url: component.url, name: component.url.lastPathComponent, kind: component.kind,
            bytes: component.bytes, outcome: outcome, dryRun: dryRun)
    }

    private func appResult(_ plan: UninstallPlan, outcome: UninstallOutcome, dryRun: Bool) -> UninstallResult {
        UninstallResult(
            url: plan.app.url, name: plan.app.name, kind: .application, bytes: plan.appBytes,
            outcome: outcome, dryRun: dryRun)
    }

    private func logReport(_ report: UninstallReport) {
        guard let log else { return }
        for row in report.results {
            log.append(
                category: "applications", path: row.url.path, bytes: row.bytes, mode: .trash,
                result: row.outcome.logValue, dryRun: report.dryRun)
        }
    }

    // MARK: - Path helpers

    static func isInside(_ url: URL, _ folder: URL) -> Bool {
        let path = canonicalPath(url)
        let base = canonicalPath(folder)
        return path == base || path.hasPrefix(base + "/")
    }

    /// `realpath(3)` resolves the `/var` -> `/private/var` symlink that
    /// `URL.standardizedFileURL` leaves in place, so a temp home compares equal to the
    /// URLs Foundation returns from `contentsOfDirectory`.
    static func canonicalPath(_ url: URL) -> String {
        FS.canonicalPath(url)
    }

    static func isWritable(_ url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return access(path, W_OK) == 0
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}
