import Foundation

/// The verdict on a whole batch, computed before the first removal. A refused batch is
/// never partially applied: the caller gets an empty accepted list and one reason.
public struct FixReport: Sendable, Equatable {
    public struct Rejection: Sendable, Equatable {
        public let url: URL
        public let reason: RefusalReason

        public init(url: URL, reason: RefusalReason) {
            self.url = url
            self.reason = reason
        }
    }

    public var accepted: [ScanItem]
    public var rejected: [Rejection]
    public var refusal: RefusalReason?

    public init(accepted: [ScanItem] = [], rejected: [Rejection] = [], refusal: RefusalReason? = nil) {
        self.accepted = accepted
        self.rejected = rejected
        self.refusal = refusal
    }
}

public struct PathFixReport: Sendable, Equatable {
    public var accepted: [URL]
    public var rejected: [FixReport.Rejection]
    public var refusal: RefusalReason?

    public init(accepted: [URL] = [], rejected: [FixReport.Rejection] = [], refusal: RefusalReason? = nil) {
        self.accepted = accepted
        self.rejected = rejected
        self.refusal = refusal
    }
}

/// The batch gate. It runs before the first removal and refuses the whole batch on the
/// first failing check, so a malformed selection can never be half-applied.
public enum BatchGuard {
    public static let maxItems = 10_000

    public static func validate(_ items: [ScanItem], policy: SafetyPolicy, roots: [URL]) -> FixReport {
        let (refusal, rejected) = check(paths: items.map(\.url), policy: policy, roots: roots)
        guard let refusal else { return FixReport(accepted: items) }
        return FixReport(rejected: rejected, refusal: refusal)
    }

    public static func validate(paths: [URL], policy: SafetyPolicy, roots: [URL]) -> PathFixReport {
        let (refusal, rejected) = check(paths: paths, policy: policy, roots: roots)
        guard let refusal else { return PathFixReport(accepted: paths) }
        return PathFixReport(rejected: rejected, refusal: refusal)
    }

    /// Every root a batch may touch: the resolved roots of the rules the scope allows, the
    /// scope's own roots, the external roots, home, and the two Applications folders.
    public static func roots(
        for scope: ScanScope, rules: [Rule], home: URL, externalRoots: [URL]
    ) -> [URL] {
        let allowed = scope.categories.isEmpty ? rules : rules.filter { scope.categories.contains($0.category) }
        var paths = allowed.flatMap { rule in
            rule.roots.map { root in
                root.hasPrefix("/") ? root : home.appendingPathComponent(root).path
            }
        }
        paths.append(contentsOf: scope.roots)
        paths.append(contentsOf: externalRoots.map(\.path))
        paths.append(home.path)
        paths.append("/Applications")
        paths.append(home.appendingPathComponent("Applications").path)

        var seen = Set<String>()
        return paths.compactMap { path in
            let standardized = URL(fileURLWithPath: path).standardizedFileURL
            return seen.insert(standardized.path).inserted ? standardized : nil
        }
    }

    private static func check(
        paths: [URL], policy: SafetyPolicy, roots: [URL]
    ) -> (RefusalReason?, [FixReport.Rejection]) {
        if paths.isEmpty { return (.batchEmpty, []) }
        if paths.count > maxItems { return (.batchTooLarge, []) }

        let malformed = paths.filter { !isWellFormed($0) }
        if !malformed.isEmpty {
            return (.batchMalformed, malformed.map { .init(url: $0, reason: .batchMalformed) })
        }

        let rootPaths = roots.map { FS.canonicalPath($0) }
        let outside = paths.filter { path in
            let candidate = FS.canonicalPath(path)
            return !rootPaths.contains { candidate == $0 || candidate.hasPrefix($0 + "/") }
        }
        if !outside.isEmpty {
            return (.batchOutsideRoot, outside.map { .init(url: $0, reason: .batchOutsideRoot) })
        }

        let denied = paths.compactMap { path -> FixReport.Rejection? in
            policy.denialReason(for: path).map { .init(url: path, reason: $0) }
        }
        if let first = denied.first { return (first.reason, denied) }

        return (nil, [])
    }

    private static func isWellFormed(_ url: URL) -> Bool {
        let path = url.path
        guard path.hasPrefix("/"), path != "/" else { return false }
        return !path.split(separator: "/").contains("..")
    }
}
