import Darwin
import Foundation

public enum ReadScope: Sendable, Equatable, CaseIterable {
    case categoryRoot, diskMapOnly, systemProtected, otherUser, rootFile, vanished, other

    static let protectedRoots = [
        "/System",
        "/private/var/db",
        "/.Spotlight-V100",
        "/.fseventsd",
        "/Library/Application Support/com.apple.TCC",
        "/Library/Mail",
        "/Library/Messages",
        "/Library/Safari",
    ]

    public static func classify(_ error: WalkError, roots: [String]) -> ReadScope {
        switch error.errno {
        case ENOENT, ELOOP: return .vanished
        case ENOTDIR where !error.url.hasDirectoryPath: return .rootFile
        default: break
        }
        let path = normalized(error.url.path)
        if roots.contains(where: { isInside(path, root: $0) }) { return .categoryRoot }
        if protectedRoots.contains(where: { isInside(path, root: $0) }) { return .systemProtected }
        let home = normalized(FileManager.default.homeDirectoryForCurrentUser.path)
        if isInside(path, root: home) { return .diskMapOnly }
        if isInside(path, root: "/Users") { return .otherUser }
        return .other
    }

    public static func blockingCount(_ errors: [WalkError], roots: [String]) -> Int {
        errors.filter { classify($0, roots: roots) == .categoryRoot }.count
    }

    static func normalized(_ path: String) -> String {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard standardized.count > 1, standardized.hasSuffix("/") else { return standardized }
        return String(standardized.dropLast())
    }

    static func isInside(_ path: String, root: String) -> Bool {
        let base = normalized(root)
        if base == "/" { return path.hasPrefix("/") }
        return path == base || path.hasPrefix(base + "/")
    }
}
