import Foundation

/// Where the duplicate finder looks for copies. The default `.standard` skips
/// regenerable project build dirs, caches, and other temporary places: deleting one
/// copy of a cache artifact rarely frees real space, and hashing them costs the
/// scan minutes. `.everything` restores the unscoped walk for users who want it.
public enum DuplicateScope: Sendable, Equatable {
    case standard
    case everything

    /// Project build dir names, shared with the "Project build dirs" rule
    /// (`Rules.rules` uses the same set as its `recursiveNames`).
    public static let regenerableNames: Set<String> = [
        "target", "node_modules", "vendor", ".build", ".gradle", "DerivedData", "Pods",
    ]

    /// Well-known cache and temporary folder names found inside user folders.
    static let tempNames: Set<String> = ["Caches", ".cache", "tmp", "temp", ".tmp"]

    /// Path components the standard scope never hashes duplicates in.
    static var skippedComponents: Set<String> { regenerableNames.union(tempNames) }

    /// Drops candidates under skipped folders. `.everything` passes the list through
    /// untouched, so opting in is exactly yesterday's behavior.
    public static func filter(_ entries: [WalkEntry], scope: Self) -> [WalkEntry] {
        guard scope == .standard, !entries.isEmpty else { return entries }
        return entries.filter { entry in
            // Parse once at this edge: exact component equality, no substring matches
            // (a file named "temp.txt" must never be excluded).
            !entry.url.pathComponents.contains { skippedComponents.contains($0) }
        }
    }
}
