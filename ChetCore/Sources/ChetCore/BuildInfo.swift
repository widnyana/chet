import Foundation

/// Facts read from the app bundle for the About window. Optional fields mean
/// the key is absent or unresolved; the window says `Unknown` rather than
/// inventing a version.
public struct BuildInfo: Sendable, Equatable {
    public let version: String?
    public let build: String?
    public let minimumOS: String?
    public let commit: String?
    public let builtAt: String?

    public init(
        version: String?, build: String?, minimumOS: String?,
        commit: String? = nil, builtAt: String? = nil
    ) {
        self.version = version
        self.build = build
        self.minimumOS = minimumOS
        self.commit = commit
        self.builtAt = builtAt
    }

    public static func current(bundle: Bundle = .main) -> BuildInfo {
        let info = bundle.infoDictionary ?? [:]
        return BuildInfo(
            version: info["CFBundleShortVersionString"] as? String,
            build: info["CFBundleVersion"] as? String,
            minimumOS: resolved(info["LSMinimumSystemVersion"] as? String),
            commit: resolved(info["ChetGitCommit"] as? String),
            builtAt: resolved(info["ChetBuildDate"] as? String))
    }

    public var shortCommit: String? {
        commit.map { String($0.prefix(7)) }
    }

    public var builtDate: Date? {
        guard let builtAt else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: builtAt) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: builtAt)
    }

    /// An absent, empty, or unexpanded build setting is not a fact about the
    /// build and must not be shown as one.
    private static func resolved(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
    }
}
