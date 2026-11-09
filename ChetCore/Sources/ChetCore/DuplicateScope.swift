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
    /// `.vite` and `.next` usually sit under `node_modules` or a project root, and `.turbo`
    /// caches Turborepo task output; all three rebuild from source. `build` and `.dart_tool`
    /// are Flutter output: `flutter build` and `flutter pub get` recreate them.
    public static let regenerableNames: Set<String> = [
        "target", "node_modules", "vendor", ".build", ".gradle", "DerivedData", "Pods", ".vite", ".next",
        ".turbo", "build", ".dart_tool",
    ]

    /// Well-known cache and temporary folder names found inside user folders.
    static let tempNames: Set<String> = ["Caches", ".cache", "tmp", "temp", ".tmp"]

    /// Hidden per-project tool state dirs; regenerable, never worth hashing.
    public static let toolStateNames: Set<String> = [".terraform", ".terragrunt-cache"]

    /// Path components the standard scope never hashes duplicates in. Stored, not computed:
    /// the duplicate filter reads it once per walked entry.
    static let skippedComponents: Set<String> = regenerableNames.union(toolStateNames).union(tempNames)

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
