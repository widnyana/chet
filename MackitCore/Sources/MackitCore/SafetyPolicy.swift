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
    }

    public func isDeletable(_ url: URL) -> Verdict {
        let standard = url.standardizedFileURL
        let path = standard.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(standard.lastPathComponent).path
        let parts = path.split(separator: "/").map(String.init)
        let inVolumeTrash = parts.count > 4 && parts[0] == "Volumes" && parts[2] == ".Trashes"
        let rel = relative(path)

        if rel == nil && !inVolumeTrash {
            if !externalRoots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
                return .denied("outside home")
            }
        }
        if let rel {
            if Self.containerRoots.contains(rel) { return .denied("container folder") }
            if Self.protectedInHome.contains(where: { rel == $0 || rel.hasPrefix($0 + "/") }) {
                return .denied("protected folder")
            }
        }
        let inTrash = inVolumeTrash || rel?.hasPrefix(".Trash/") == true
        if !inTrash {
            if parts.contains(".git") { return .denied("git repository") }
            if Self.containsAppBundle(parts) { return .denied("app bundle") }
            if parts.contains(where: { $0.hasSuffix(".photoslibrary") }) { return .denied("Photos library") }
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

    private func relative(_ path: String) -> String? {
        if path == home { return "" }
        guard path.hasPrefix(home + "/") else { return nil }
        return String(path.dropFirst(home.count + 1))
    }
}
