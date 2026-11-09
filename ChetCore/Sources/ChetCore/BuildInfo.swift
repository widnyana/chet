import Foundation

/// Facts read from the app bundle for the About window. Optional fields mean
/// the key is absent or unresolved; the window says `Unknown` rather than
/// inventing a version.
public struct BuildInfo: Sendable, Equatable {
    public let version: String?
    public let build: String?
    public let minimumOS: String?

    public init(version: String?, build: String?, minimumOS: String?) {
        self.version = version
        self.build = build
        self.minimumOS = minimumOS
    }

    public static func current(bundle: Bundle = .main) -> BuildInfo {
        let info = bundle.infoDictionary ?? [:]
        return BuildInfo(
            version: info["CFBundleShortVersionString"] as? String,
            build: info["CFBundleVersion"] as? String,
            minimumOS: expandedMinimumOS(info["LSMinimumSystemVersion"] as? String))
    }

    /// An unexpanded build setting means the value was not resolved into the
    /// built bundle, so it is not a version and must not be shown as one.
    private static func expandedMinimumOS(_ value: String?) -> String? {
        guard let value, !value.contains("$(") else { return nil }
        return value
    }
}
