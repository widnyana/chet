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
    public let home: URL
    public let rules: [Rule]
    public let policy: SafetyPolicy

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, rules: [Rule] = Rule.catalog) {
        self.home = home
        self.rules = rules
        policy = SafetyPolicy(home: home)
    }

    public func scan(_ rule: Rule, now: Date = Date()) throws -> CategoryResult {
        var result = CategoryResult(ruleID: rule.id, category: rule.category, items: [], needsFullDiskAccess: false)
        // Roots of other rules are scanned by those rules, so a parent rule skips them.
        let claimed = rules.filter { $0.id != rule.id }.flatMap(\.roots)
        for root in rule.roots {
            let rootURL = home.appendingPathComponent(root)
            let children: [URL]
            do {
                let listed = try FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)
                children = rule.wholeRoots ? [rootURL] : listed
            } catch CocoaError.fileReadNoPermission {
                result.needsFullDiskAccess = true
                continue
            } catch {
                continue
            }
            var found: [ScanItem] = []
            for child in children {
                try Task.checkCancellation()
                if child.lastPathComponent == ".DS_Store" { continue }
                let name = child.lastPathComponent
                let rel = rule.wholeRoots ? root : root + "/" + name
                if rule.excluded.contains(name) { continue }
                if claimed.contains(where: { $0 == rel || $0.hasPrefix(rel + "/") }) { continue }
                if let extensions = rule.extensions, !extensions.contains(child.pathExtension.lowercased()) { continue }
                guard policy.isDeletable(child) == .allowed, let stamp = FileStamp.read(child) else { continue }
                if let minAge = rule.minAge, now.timeIntervalSince(stamp.modified) < minAge { continue }
                let bytes = FileIndexBuilder.allocatedSize(of: child)
                guard bytes > 0 else { continue }
                found.append(
                    ScanItem(
                        url: child, categoryID: rule.category, risk: rule.risk, mode: rule.mode,
                        reclaimableBytes: bytes, stamp: stamp, ownerBundleID: rule.owningBundleID))
            }
            if rule.keepNewest, let newest = found.max(by: { $0.stamp.modified < $1.stamp.modified }) {
                found.removeAll { $0.url == newest.url }
            }
            result.items += found
        }
        return result
    }

    /// Scans every rule in parallel and yields each result as soon as it is ready.
    public func scanAll() -> AsyncStream<CategoryResult> {
        AsyncStream { continuation in
            let task = Task {
                await withTaskGroup(of: CategoryResult?.self) { group in
                    for rule in rules {
                        group.addTask { try? self.scan(rule) }
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
