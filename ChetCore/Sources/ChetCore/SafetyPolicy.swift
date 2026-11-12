import Darwin
import Foundation

public enum Verdict: Equatable, Sendable {
    case allowed
    case denied(String)
}

/// The one gate every scanner and the cleaner pass a path through.
public struct SafetyPolicy: Sendable {
    public let home: String
    /// Absolute paths (e.g. "/nix/var/nix/profiles") that bypass the home check.
    public let externalRoots: Set<String>
    /// Settings opt-in: paths outside the home folder pass the home check; the other rules still apply.
    public let allowsOutsideHome: Bool
    /// Settings list: a path equal to or below an entry is never scanned or cleaned.
    public let excludedPaths: [String]
    /// The realpath(3) form of `home`. Foundation's `resolvingSymlinksInPath` leaves the `/var`
    /// symlink as `/var`, while the directory walk (openat/readdir) yields `/private/var`; both
    /// forms name the same folder, so path rules must accept either.
    private let realHome: String

    static let protectedInHome = ["Library/Keychains", "Library/Mobile Documents", "Library/Messages", "Library/Mail"]
    static let containerRoots: Set<String> = [
        "", "Library", "Library/Caches", "Library/Logs", "Library/Application Support", "Library/Preferences",
        "Library/Containers", "Library/Group Containers", "Library/Developer", "Documents", "Desktop",
        "Downloads", "Pictures", "Movies", "Music", "Applications", ".Trash",
    ]

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        externalRoots: Set<String> = [],
        allowsOutsideHome: Bool = false,
        excludedPaths: [String] = []
    ) {
        self.home = home.resolvingSymlinksInPath().path
        // A root arrives in whichever spelling its caller used: realpath(3) and the folder walk
        // yield `/private/var/...`, while `resolvingSymlinksInPath` (the spelling `isDeletable`
        // builds) yields `/var/...`. Keep both so a root matches the path it will be compared to.
        self.externalRoots = externalRoots.reduce(into: Set<String>()) { roots, root in
            roots.insert(root)
            roots.insert(URL(fileURLWithPath: root).resolvingSymlinksInPath().path)
        }
        self.allowsOutsideHome = allowsOutsideHome
        self.excludedPaths = Self.normalize(excludedPaths, home: home)
        self.realHome =
            home.path.withCString { realpath($0, nil) }.map { String(cString: $0) } ?? self.home
    }

    /// `~/x` resolves against `home`, `/x` stays absolute, anything else is dropped: a relative
    /// entry would silently exclude nothing. Both the standardized and the symlink-resolved
    /// spelling are kept, because the rule walk and the deletion check build paths differently.
    static func normalize(_ paths: [String], home: URL) -> [String] {
        let base = home.standardizedFileURL.path
        return paths.flatMap { raw -> [String] in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return [] }
            let resolved: String
            if trimmed == "~" {
                resolved = base
            } else if trimmed.hasPrefix("~/") {
                resolved = base + "/" + trimmed.dropFirst(2)
            } else if trimmed.hasPrefix("/") {
                resolved = trimmed
            } else {
                return []
            }
            let url = URL(fileURLWithPath: resolved)
            let standardized = url.standardizedFileURL.path
            let symlinked = url.deletingLastPathComponent().resolvingSymlinksInPath()
                .appendingPathComponent(url.lastPathComponent).path
            return standardized == symlinked ? [standardized] : [standardized, symlinked]
        }
    }

    /// The rule walk uses this to stop descending into an excluded tree.
    public func isExcluded(_ url: URL) -> Bool {
        guard !excludedPaths.isEmpty else { return false }
        let path = url.standardizedFileURL.path
        return excludedPaths.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    /// The path-string rules shared by `denialReason(for:)` and `scanGateAllows`, in one place
    /// so the scan gate can never drift out of the policy. Returns the denial reason, or nil
    /// when no path rule denies the file.
    private func denialReason(
        path: String, rel: String?, parts: [String], inVolumeTrash: Bool
    ) -> RefusalReason? {
        if !excludedPaths.isEmpty, excludedPaths.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
            return .excludedFolder
        }
        if rel == nil && !inVolumeTrash && !isExternal(path) && !allowsOutsideHome { return .outsideHome }
        if let rel {
            if Self.containerRoots.contains(rel) { return .containerFolder }
            if Self.protectedInHome.contains(where: { rel == $0 || rel.hasPrefix($0 + "/") }) {
                return .protectedFolder
            }
        }
        let inTrash = inVolumeTrash || rel?.hasPrefix(".Trash/") == true
        if !inTrash {
            if parts.contains(".git") { return .gitRepository }
            if Self.containsAppBundle(parts) { return .appBundle }
            if parts.contains(where: { $0.hasSuffix(".photoslibrary") }) { return .photosLibrary }
        }
        return nil
    }

    /// True when `path` sits under one of the policy's absolute roots.
    private func isExternal(_ path: String) -> Bool {
        externalRoots.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    /// Paths no engine may remove, whatever its own identification rules say: the system and
    /// private trees, and the home folders macOS protects. Symlinks are resolved first, so a
    /// link cannot smuggle a protected path past the check.
    public func isProtectedPath(_ url: URL) -> Bool {
        let path = FS.canonicalPath(url)
        let systemPrefixes = [
            "/System", "/usr", "/bin", "/sbin", "/private/etc", "/private/var/db", "/private/var/root",
            "/Library/Apple", "/Library/Extensions", "/Library/Frameworks", "/Library/Keychains",
            "/Library/Mail", "/Library/Messages",
        ]
        if systemPrefixes.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return true }
        let homePath = FS.canonicalPath(URL(fileURLWithPath: home))
        guard path.hasPrefix(homePath + "/") else { return false }
        let rel = String(path.dropFirst(homePath.count + 1))
        let homePrefixes = [
            "Library/Keychains", "Library/Mail", "Library/Messages", "Library/Mobile Documents", ".Trash",
        ]
        return homePrefixes.contains { rel == $0 || rel.hasPrefix($0 + "/") }
    }

    /// The full verdict for one path: the path rules, then the `lstat` symlink and mount-point
    /// checks. `isDeletable` and the batch guard both read this, so there is one authority.
    public func denialReason(for url: URL) -> RefusalReason? {
        let standard = url.standardizedFileURL
        let path = standard.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(standard.lastPathComponent).path
        let parts = path.split(separator: "/").map(String.init)
        let inVolumeTrash = parts.count > 4 && parts[0] == "Volumes" && parts[2] == ".Trashes"
        // Only the Foundation spelling here: isDeletable has always resolved the parent itself,
        // and the external-root test pins its behavior on that spelling.
        let rel = relative(path, bases: [home])

        if let reason = denialReason(
            path: path, rel: rel, parts: parts, inVolumeTrash: inVolumeTrash
        ) {
            return reason
        }

        var st = stat()
        var parent = stat()
        if lstat(path, &st) == 0 {
            if (st.st_mode & S_IFMT) == S_IFLNK { return .symlink }
            if lstat((path as NSString).deletingLastPathComponent, &parent) == 0, st.st_dev != parent.st_dev {
                return .mountPoint
            }
        }
        return nil
    }

    public func isDeletable(_ url: URL) -> Verdict {
        denialReason(for: url).map { Verdict.denied($0.rawValue) } ?? .allowed
    }

    /// Scan-time narrowing gate for the bulk walk: mirrors `isDeletable`'s bulk-visible rules —
    /// path strings, object type, and the device comparison — without paying a per-file `lstat` or
    /// parent-path resolution. `url` must be the canonical path the walk built (real directory
    /// components). The gate may over-include (a candidate it passes can still be denied by the
    /// full check at clean time) but never under-include. The full `isDeletable` check
    /// immediately before deletion stays the only deletion authority.
    public func scanGateAllows(_ url: URL, isSymlink: Bool, device: dev_t, parentDevice: dev_t) -> Bool {
        // Walk paths are already canonical, so the standardizing pass is skipped here.
        let path = url.path
        let parts = path.split(separator: "/").map(String.init)
        let inVolumeTrash = parts.count > 4 && parts[0] == "Volumes" && parts[2] == ".Trashes"
        // Walk paths use the realpath(3) spelling, so the gate accepts both.
        let rel = relative(path, bases: [home, realHome])
        if denialReason(path: path, rel: rel, parts: parts, inVolumeTrash: inVolumeTrash) != nil {
            return false
        }
        if isSymlink { return false }
        if device != parentDevice { return false }
        return true
    }

    /// A component ending in `.app` is an app bundle when it holds `Contents`: the path goes into
    /// `Contents`, or the folder on disk has `Contents/Info.plist`. Cache folders named after bundle IDs,
    /// like `com.example.app`, are not bundles.
    static func containsAppBundle(_ parts: [String]) -> Bool {
        for (index, part) in parts.enumerated() where part.hasSuffix(".app") {
            if index + 1 < parts.count, parts[index + 1] == "Contents" { return true }
            let bundle = "/" + parts[...index].joined(separator: "/")
            if FileManager.default.fileExists(atPath: bundle + "/Contents/Info.plist") { return true }
        }
        return false
    }

    private func relative(_ path: String, bases: [String]) -> String? {
        for base in bases {
            if path == base { return "" }
            if path.hasPrefix(base + "/") { return String(path.dropFirst(base.count + 1)) }
        }
        return nil
    }
}
