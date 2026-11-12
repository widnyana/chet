import Foundation

public struct CategoryResult: Sendable {
    public let ruleID: String
    public let category: String
    public var items: [ScanItem]
    /// A root folder exists but could not be read: macOS Full Disk Access is missing.
    public var needsFullDiskAccess: Bool
    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.reclaimableBytes } }
}

public struct PnpmStoreResolver: Sendable {
    public let storePath: @Sendable () -> String?
    public let exists: @Sendable (String) -> Bool

    public init(storePath: @escaping @Sendable () -> String?, exists: @escaping @Sendable (String) -> Bool) {
        self.storePath = storePath
        self.exists = exists
    }

    public static let live = PnpmStoreResolver(
        storePath: { queryStorePath() },
        exists: { path in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        })

    private static func queryStorePath() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["pnpm", "store", "path"]
        let output = Pipe()
        process.standardOutput = output
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }
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

    public let home: URL
    public let rules: [Rule]
    public let policy: SafetyPolicy
    /// The complete rule list, used only to decide which roots another rule owns. Filtering
    /// `rules` for a scan must not make a parent rule claim roots it no longer covers.
    let claimingRules: [Rule]
    let pnpmStore: PnpmStoreResolver

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser, rules: [Rule] = Rule.catalog,
        claimingRules: [Rule]? = nil, allowOutsideHome: Bool = false, excludedPaths: [String] = [],
        pnpmStore: PnpmStoreResolver = .live
    ) {
        self.home = home
        self.rules = rules
        self.claimingRules = claimingRules ?? rules
        self.pnpmStore = pnpmStore
        let absoluteRoots = Set(
            (claimingRules ?? rules).flatMap { $0.roots }.filter { $0.hasPrefix("/") })
        policy = SafetyPolicy(
            home: home, externalRoots: absoluteRoots, allowsOutsideHome: allowOutsideHome,
            excludedPaths: excludedPaths)
    }

    public func scan(_ rule: Rule, now: Date = Date()) async throws -> CategoryResult {
        var result = CategoryResult(ruleID: rule.id, category: rule.category, items: [], needsFullDiskAccess: false)
        // Roots of other rules are scanned by those rules, so a parent rule skips them.
        let claimed = claimingRules.filter { $0.id != rule.id }.flatMap(\.roots)
        for root in rule.roots + discoveryRoots(for: rule) {
            let rootURL: URL = root.hasPrefix("/") ? URL(fileURLWithPath: root) : home.appendingPathComponent(root)
            let isAbsolute = root.hasPrefix("/")
            var candidates: [(url: URL, kind: String?)]
            if let artifacts = rule.recursiveArtifacts {
                candidates = []
                try recursiveMatches(
                    rootURL, artifacts: artifacts, pruning: rule.prunedNames,
                    venvs: rule.matchesVirtualEnvironments, into: &candidates)
            } else if let names = rule.recursiveNames {
                candidates = []
                try recursiveMatches(
                    rootURL, names: names, pruning: rule.prunedNames,
                    venvs: rule.matchesVirtualEnvironments, into: &candidates)
            } else {
                do {
                    let listed = try FileManager.default.contentsOfDirectory(
                        at: rootURL, includingPropertiesForKeys: nil)
                    let kind = rule.wholeRoots ? BuildArtifact.label(forRoot: root) : nil
                    candidates = (rule.wholeRoots ? [rootURL] : listed).map { (url: $0, kind: kind) }
                } catch CocoaError.fileReadNoPermission {
                    result.needsFullDiskAccess = true
                    continue
                } catch {
                    continue
                }
            }
            var found: [ScanItem] = []
            for (child, kind) in candidates {
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
                let demoted = rule.reviewNames.contains(name) || rule.reviewPrefixes.contains { name.hasPrefix($0) }
                let owner = rule.childNamesAreBundleIDs && Self.isReverseDNSIdentifier(name) ? name : nil
                found.append(
                    ScanItem(
                        url: child, categoryID: rule.category, risk: holdsState || demoted ? .review : rule.risk,
                        mode: holdsState || demoted ? .trash : rule.mode,
                        reclaimableBytes: bytes, stamp: stamp, ownerBundleID: owner ?? rule.owningBundleID,
                        requiresAdmin: rule.requiresAdmin, kind: kind, sizeBasis: .allocated))
            }
            if rule.keepNewest, let newest = found.max(by: { $0.stamp.modified < $1.stamp.modified }) {
                found.removeAll { $0.url == newest.url }
            }
            result.items += found
        }
        return result
    }

    /// Depth-first search under `root` for directories named in `names` or matching an entry in
    /// `artifacts`. A matched directory becomes one item and is never descended into; `.git` is
    /// never entered, and `pruning` names are neither matched nor entered when another rule owns
    /// them. Package stores are skipped whole, so a `node_modules` inside one is never an item.
    /// Depth is capped so a pathological tree cannot make the scan unbounded.
    /// Matches accumulate into one array, so the walk never copies its results per level.
    private func recursiveMatches(
        _ root: URL, names: Set<String> = [], artifacts: [BuildArtifact]? = nil,
        pruning: Set<String> = [], venvs: Bool = false,
        into found: inout [(url: URL, kind: String?)], depth: Int = 0
    ) throws {
        guard depth <= Self.maxScanDepth else { return }
        let children = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
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
            if BuildArtifact.isPackageStore(child) { continue }
            if pruning.contains(name) { continue }
            if Self.matches(child, name: name, names: names, artifacts: artifacts, venvs: venvs) {
                found.append((child, Self.kind(for: child, artifacts: artifacts)))
            } else {
                try recursiveMatches(
                    child, names: names, artifacts: artifacts, pruning: pruning, venvs: venvs,
                    into: &found, depth: depth + 1)
            }
        }
    }

    private static func matches(
        _ url: URL, name: String, names: Set<String>, artifacts: [BuildArtifact]?, venvs: Bool
    ) -> Bool {
        if names.contains(name) { return true }
        if venvs, BuildArtifact.isVirtualEnvironment(url) { return true }
        guard let artifacts else { return false }
        return BuildArtifact.label(for: url, in: artifacts) != nil
    }

    private static func isReverseDNSIdentifier(_ name: String) -> Bool {
        !name.contains(where: \.isWhitespace) && name.filter { $0 == "." }.count >= 2
    }

    /// Tool label for a matched build directory, nil outside the build-artifact rules.
    private static func kind(for url: URL, artifacts: [BuildArtifact]?) -> String? {
        BuildArtifact.label(for: url, in: artifacts ?? BuildArtifact.catalog)
    }

    /// Absolute roots a rule learns only at scan time (tool registries, custom install paths).
    private func discoveryRoots(for rule: Rule) -> [String] {
        guard let discovery = rule.discovery else { return [] }
        switch discovery {
        case .virtualBoxMachines:
            return VirtualBoxMachines.folders(home: home).map(\.path)
        case .pnpmStore:
            return pnpmStoreRoots()
        }
    }

    private func pnpmStoreRoots() -> [String] {
        var candidates: [String] = []
        if let path = pnpmStore.storePath(), !path.isEmpty {
            candidates.append(path)
        }
        if let root = ProcessInfo.processInfo.environment["PNPM_HOME"], !root.isEmpty {
            candidates.append(
                URL(fileURLWithPath: root, isDirectory: true).appendingPathComponent("store").path)
        }
        candidates.append(home.appendingPathComponent(".local/share/pnpm/store").path)
        candidates.append(home.appendingPathComponent("Library/pnpm/store").path)
        for candidate in candidates where pnpmStore.exists(candidate) {
            return [candidate]
        }
        return []
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
