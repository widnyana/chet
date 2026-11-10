import Foundation

/// What one scan is allowed to look at. An empty value scans everything the way Chet always
/// has; categories or roots narrow that, and nothing here can widen `SafetyPolicy`.
public struct ScanScope: Sendable, Equatable, Codable {
    public var categories: Set<String>
    public var roots: [String]

    public init(categories: Set<String> = [], roots: [String] = []) {
        self.categories = categories
        self.roots = roots
    }

    public static let everywhere = ScanScope()

    public var isPartial: Bool { !categories.isEmpty || !roots.isEmpty }

    public static let stepCategories: [ScanStep: Set<String>] = [
        .index: ["tagged-caches"],
        .largeFiles: ["large-files"],
        .duplicates: ["duplicates"],
        .leftovers: ["leftovers"],
        .photos: ["similar-photos", "blurry-photos"],
        .videos: ["similar-videos"],
        .snapshots: ["snapshots"],
    ]

    /// Categories that need the folder index.
    public static let measurementCategories: Set<String> = [
        "tagged-caches", "large-files", "duplicates", "similar-photos", "blurry-photos",
        "similar-videos",
    ]

    /// Categories the rules step reports: one per catalog rule, plus the user's own folders.
    public static let ruleCategories: Set<String> =
        Set(Rule.catalog.map(\.category)).union([UserRule.category])

    /// Every category a scope may name, in catalog order.
    public static let knownCategories: [String] = {
        var ordered: [String] = []
        for rule in Rule.catalog where !ordered.contains(rule.category) {
            ordered.append(rule.category)
        }
        for extra in [UserRule.category] + ["tagged-caches", "large-files", "duplicates", "leftovers"] {
            if !ordered.contains(extra) { ordered.append(extra) }
        }
        for category in ["similar-photos", "blurry-photos", "similar-videos", "snapshots"]
        where !ordered.contains(category) {
            ordered.append(category)
        }
        return ordered
    }()

    /// The index is needed when a measurement category is selected or the roots are restricted.
    public var needsIndex: Bool {
        if !roots.isEmpty { return true }
        if categories.isEmpty { return true }
        return !categories.isDisjoint(with: Self.measurementCategories)
    }

    /// Whether a step may run under this scope. `.rules` and `.index` are never switched off by
    /// the settings; this is the only place that can drop them.
    public func runs(_ step: ScanStep) -> Bool {
        if step == .index { return needsIndex }
        if categories.isEmpty { return true }
        if let produced = Self.stepCategories[step] {
            return !categories.isDisjoint(with: produced)
        }
        return !categories.isDisjoint(with: Self.ruleCategories)
    }

    /// Unknown ids and relative roots are dropped rather than kept as a filter that matches
    /// nothing. Roots are absolute, standardized and unique.
    public func normalized() -> ScanScope {
        var seen = Set<String>()
        let cleaned = roots.compactMap { raw -> String? in
            guard raw.hasPrefix("/") else { return nil }
            let path = URL(fileURLWithPath: raw).standardizedFileURL.path
            guard path != "/" else { return nil }
            return seen.insert(path).inserted ? path : nil
        }
        return ScanScope(
            categories: categories.filter(Self.knownCategories.contains), roots: cleaned)
    }
}
