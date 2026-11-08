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
        externalRoots: Set<String> = []
    ) {
        self.home = home.resolvingSymlinksInPath().path
        self.externalRoots = externalRoots
        self.realHome =
            home.path.withCString { realpath($0, nil) }.map { String(cString: $0) } ?? self.home
    }

    /// The path-string rules shared by `isDeletable` and `scanGateAllows`, in one place so the
    /// scan gate can never drift out of the policy. Returns the denial reason, or nil when no
    /// path rule denies the file.
    private func pathDenialReason(
        path: String, rel: String?, parts: [String], inVolumeTrash: Bool
    ) -> String? {
        if rel == nil && !inVolumeTrash && !isExternal(path) { return "outside home" }
        if let rel {
            if Self.containerRoots.contains(rel) { return "container folder" }
            if Self.protectedInHome.contains(where: { rel == $0 || rel.hasPrefix($0 + "/") }) {
                return "protected folder"
            }
        }
        let inTrash = inVolumeTrash || rel?.hasPrefix(".Trash/") == true
        if !inTrash {
            if parts.contains(".git") { return "git repository" }
            if Self.containsAppBundle(parts) { return "app bundle" }
            if parts.contains(where: { $0.hasSuffix(".photoslibrary") }) { return "Photos library" }
        }
        return nil
    }

    /// True when `path` sits under one of the policy's absolute roots.
    private func isExternal(_ path: String) -> Bool {
        externalRoots.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    public func isDeletable(_ url: URL) -> Verdict {
        let standard = url.standardizedFileURL
        let path = standard.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(standard.lastPathComponent).path
        let parts = path.split(separator: "/").map(String.init)
        let inVolumeTrash = parts.count > 4 && parts[0] == "Volumes" && parts[2] == ".Trashes"
        // Only the Foundation spelling here: isDeletable has always resolved the parent itself,
        // and the external-root test pins its behavior on that spelling.
        let rel = relative(path, bases: [home])

        if let reason = pathDenialReason(
            path: path, rel: rel, parts: parts, inVolumeTrash: inVolumeTrash
        ) {
            return .denied(reason)
        }

        var st = stat()
        var parent = stat()
        if lstat(path, &st) == 0 {
            if (st.st_mode & S_IFMT) == S_IFLNK { return .denied("symlink") }
            if lstat((path as NSString).deletingLastPathComponent, &parent) == 0, st.st_dev != parent.st_dev {
                return .denied("mount point")
            }
        }
        return .allowed
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
        if pathDenialReason(path: path, rel: rel, parts: parts, inVolumeTrash: inVolumeTrash) != nil {
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
