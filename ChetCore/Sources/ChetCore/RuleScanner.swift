import Foundation

public struct CategoryResult: Sendable {
    public let ruleID: String
    public let category: String
    public var items: [ScanItem]
    /// A root folder exists but could not be read: macOS Full Disk Access is missing.
    public var needsFullDiskAccess: Bool
    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.reclaimableBytes } }
}

public struct RuleScanner: Sendable {
    /// Deepest recursion for `recursiveNames` walks. Terragrunt caches nest up to nine
    /// components below a scanned root (`.terragrunt-stack/<unit>/.terragrunt-cache`).
    /// The walk lists directories only and prunes heavy names, so the bound stays cheap.
    static let maxScanDepth = 12

    /// Version managers own their install trees. Removing a build directory inside one breaks
    /// the installed tool, so the walk never enters a mise data directory: the path named by
    /// `MISE_DATA_DIR`, or a `mise`/`.mise` folder holding an `installs` child.
    static let miseDataDirectory: String? = ProcessInfo.processInfo.environment["MISE_DATA_DIR"]
        .map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL.path }

    static func isMiseDataDirectory(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        if let root = miseDataDirectory, path == root || path.hasPrefix(root + "/") { return true }
        guard url.lastPathComponent == "mise" || url.lastPathComponent == ".mise" else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(
            atPath: url.appendingPathComponent("installs").path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// Only the environment's own bootstrapper writes `pyvenv.cfg`, so its presence identifies
    /// a virtual environment; the folder name does not (`.venv-codegen`, `venv`, `list`).
    static func isVirtualEnvironment(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(
            atPath: url.appendingPathComponent("pyvenv.cfg").path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
    }

    public let home: URL
    public let rules: [Rule]
    public let policy: SafetyPolicy

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser, rules: [Rule] = Rule.catalog,
        allowOutsideHome: Bool = false, excludedPaths: [String] = []
    ) {
        self.home = home
        self.rules = rules
        let absoluteRoots = Set(rules.flatMap { $0.roots }.filter { $0.hasPrefix("/") })
        policy = SafetyPolicy(
            home: home, externalRoots: absoluteRoots, allowsOutsideHome: allowOutsideHome,
            excludedPaths: excludedPaths)
    }

    public func scan(_ rule: Rule, now: Date = Date()) async throws -> CategoryResult {
        var result = CategoryResult(ruleID: rule.id, category: rule.category, items: [], needsFullDiskAccess: false)
        // Roots of other rules are scanned by those rules, so a parent rule skips them.
        let claimed = rules.filter { $0.id != rule.id }.flatMap(\.roots)
        for root in rule.roots + discoveryRoots(for: rule) {
            let rootURL: URL = root.hasPrefix("/") ? URL(fileURLWithPath: root) : home.appendingPathComponent(root)
            let isAbsolute = root.hasPrefix("/")
            var candidates: [URL]
            if let names = rule.recursiveNames {
                candidates = try recursiveMatches(
                    rootURL, names, pruning: rule.prunedNames, venvs: rule.matchesVirtualEnvironments)
            } else {
                do {
                    let listed = try FileManager.default.contentsOfDirectory(
                        at: rootURL, includingPropertiesForKeys: nil)
                    candidates = rule.wholeRoots ? [rootURL] : listed
                } catch CocoaError.fileReadNoPermission {
                    result.needsFullDiskAccess = true
                    continue
                } catch {
                    continue
                }
            }
            var found: [ScanItem] = []
            for child in candidates {
                try Task.checkCancellation()
                if child.lastPathComponent == ".DS_Store" { continue }
                let name = child.lastPathComponent
                let rel =
                    rule.wholeRoots
                    ? root
                    : (isAbsolute
                        ? String(child.path.dropFirst(rootURL.path.count + 1))
                        : String(child.path.dropFirst(home.path.count + 1)))
                if rule.excluded.contains(name) { continue }
                if claimed.contains(where: { $0 == rel || $0.hasPrefix(rel + "/") }) { continue }
                if let extensions = rule.extensions, !extensions.contains(child.pathExtension.lowercased()) { continue }
                guard rule.listOnly || policy.isDeletable(child) == .allowed, let stamp = FileStamp.read(child) else {
                    continue
                }
                if let minAge = rule.minAge, now.timeIntervalSince(stamp.modified) < minAge { continue }
                let bytes = await FileIndexBuilder.allocatedSize(of: child)
                guard bytes > 0 else { continue }
                // A tool dir holding Terraform state is never safe: the cleaner refuses it.
                let holdsState = TerraformState.holdsLocalState(child)
                found.append(
                    ScanItem(
                        url: child, categoryID: rule.category, risk: holdsState ? .review : rule.risk,
                        mode: holdsState ? .trash : rule.mode,
                        reclaimableBytes: bytes, stamp: stamp, ownerBundleID: rule.owningBundleID,
                        requiresAdmin: rule.requiresAdmin))
            }
            if rule.keepNewest, let newest = found.max(by: { $0.stamp.modified < $1.stamp.modified }) {
                found.removeAll { $0.url == newest.url }
            }
            result.items += found
        }
        return result
    }

    /// Depth-first search under `root` for directories whose name is in `names`. A matched
    /// directory becomes one item and is never descended into; `.git` is never entered, and
    /// `pruning` names are neither matched nor entered when another rule owns them.
    /// Depth is capped so a pathological tree cannot make the scan unbounded.
    private func recursiveMatches(
        _ root: URL, _ names: Set<String>, pruning: Set<String> = [], venvs: Bool = false, depth: Int = 0
    ) throws -> [URL] {
        guard depth <= Self.maxScanDepth else { return [] }
        let children = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        var found: [URL] = []
        for child in children {
            try Task.checkCancellation()
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: child.path, isDirectory: &isDirectory),
                isDirectory.boolValue
            else { continue }
            let name = child.lastPathComponent
            if name == ".git" { continue }
            if policy.isExcluded(child) { continue }
            if Self.isMiseDataDirectory(child) { continue }
            if venvs && Self.isVirtualEnvironment(child) {
                found.append(child)
            } else if names.contains(name) {
                found.append(child)
            } else if !pruning.contains(name) {
                found += try recursiveMatches(child, names, pruning: pruning, venvs: venvs, depth: depth + 1)
            }
        }
        return found
    }

    /// Absolute roots a rule learns only at scan time (tool registries, custom install paths).
    private func discoveryRoots(for rule: Rule) -> [String] {
        guard let discovery = rule.discovery else { return [] }
        switch discovery {
        case .virtualBoxMachines:
            return VirtualBoxMachines.folders(home: home).map(\.path)
        }
    }

    /// Scans every rule in parallel and yields each result as soon as it is ready.
    public func scanAll() -> AsyncStream<CategoryResult> {
        AsyncStream { continuation in
            let task = Task {
                await withTaskGroup(of: CategoryResult?.self) { group in
                    for rule in rules {
                        group.addTask { try? await self.scan(rule) }
                    }
                    for await result in group {
                        if let result { continuation.yield(result) }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
