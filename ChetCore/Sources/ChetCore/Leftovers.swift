import AppKit
import Foundation
import Security

/// Library entries named after a bundle ID whose app (or any app from the same vendor) is not
/// installed, is not registered with LaunchServices, and whose owner is not recorded as
/// installed by container or group-container metadata.
public struct LeftoverScanner: Sendable {
    public let home: URL
    public let policy: SafetyPolicy
    public let minAge: TimeInterval
    public let resolvesInstalled: @Sendable (String) -> Bool
    private let appFolders: [URL]
    private let apps: [InstalledApp]?
    private let teamIDs: Set<String>?

    static let folders = [
        "Library/Application Support", "Library/Preferences", "Library/Containers",
        "Library/Group Containers", "Library/Saved Application State",
    ]
    /// Data untouched this long is treated as orphaned. A live app whose bundle id differs
    /// from its data id cannot be linked by identifier, and its data is rewritten whenever it
    /// runs; age is the only general liveness signal left.
    public static let orphanAge: TimeInterval = 90 * 86_400
    /// Our own app and its test domain are never cleanup targets.
    static let ownIdentifiers: Set<String> = ["id.web.widnyana.chet", "com.chet.tweaks.tests"]

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        appFolders: [URL]? = nil,
        apps: [InstalledApp]? = nil,
        teamIDs: Set<String>? = nil,
        policy: SafetyPolicy? = nil,
        minAge: TimeInterval = LeftoverScanner.orphanAge,
        resolvesInstalled: @escaping @Sendable (String) -> Bool = LeftoverScanner.launchServicesResolves
    ) {
        self.home = home
        self.policy = policy ?? SafetyPolicy(home: home)
        self.minAge = minAge
        self.resolvesInstalled = resolvesInstalled
        self.appFolders = appFolders ?? AppUninstaller.defaultAppFolders(home: home)
        self.apps = apps
        self.teamIDs = teamIDs
    }

    public func scan() throws -> [ScanItem] {
        let installed =
            apps
            ?? AppUninstaller(
                home: home, appFolders: appFolders, searchRoots: [], policy: policy
            ).installedApps()
        // Without a readable app inventory every test below passes and live data would be
        // offered for deletion. Injected apps are trusted even when empty (tests).
        if apps == nil && installed.isEmpty { return [] }
        let installedIDs = BundleIDIndex(Set(installed.flatMap(\.allBundleIDs)))
        let vendors = Set(installed.compactMap { $0.bundleID.map(Self.vendor) })
        let teams = teamIDs ?? Set(installed.compactMap { CodeSignature.teamID(of: $0.url) })
        let walker = FileWalker(policy: policy)
        let now = Date()
        var items: [ScanItem] = []

        for folder in Self.folders {
            let entries =
                (try? FileManager.default.contentsOfDirectory(
                    at: home.appendingPathComponent(folder), includingPropertiesForKeys: nil)) ?? []
            for entry in entries {
                try Task.checkCancellation()
                guard let id = Self.bundleID(fromName: entry.lastPathComponent) else { continue }
                guard !Self.isOwn(id), !Self.isAppleOwned(id) else { continue }
                guard !installedIDs.isShared(id) else { continue }
                guard !vendors.contains(Self.vendor(id)) else { continue }
                guard !resolvesInstalled(id) else { continue }
                if folder == "Library/Containers", !Self.containerIsOrphan(entry, teams: teams) {
                    continue
                }
                if folder == "Library/Group Containers",
                    let team = Self.team(in: entry.lastPathComponent), teams.contains(team)
                {
                    continue
                }
                guard policy.isDeletable(entry) == .allowed, let stamp = FileStamp.read(entry) else {
                    continue
                }
                guard now.timeIntervalSince(stamp.modified) >= minAge else { continue }
                items.append(
                    ScanItem(
                        url: entry, categoryID: "leftovers", risk: .review, mode: .trash,
                        reclaimableBytes: try walker.totalSize(entry), stamp: stamp))
            }
        }
        return items.sorted { $0.reclaimableBytes > $1.reclaimableBytes }
    }

    /// One parser for both the uninstaller and the leftover scan, so a display name and a
    /// leftover row can never disagree about which identifier a library entry belongs to.
    static func bundleID(fromName name: String) -> String? {
        AppUninstaller.normalizedIdentifier(name)
    }

    /// First two reverse-DNS parts, lowercased: `com.google.Chrome` -> `com.google`.
    static func vendor(_ id: String) -> String {
        id.lowercased().split(separator: ".").prefix(2).joined(separator: ".")
    }

    /// LaunchServices knows every registered app, including ones outside the scanned folders.
    public static func launchServicesResolves(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    static func isOwn(_ id: String) -> Bool {
        let lower = id.lowercased()
        return ownIdentifiers.contains { lower == $0 || lower.hasPrefix($0 + ".") }
    }

    /// Apple's own data is never a cleanup target, including group/systemgroup forms.
    static func isAppleOwned(_ id: String) -> Bool {
        let lower = id.lowercased()
        return lower.hasPrefix("com.apple.") || lower.hasPrefix("is.workflow.")
    }

    /// The signing team of a container or group container name: any 10-character
    /// uppercase alphanumeric component.
    static func team(in name: String) -> String? {
        for part in name.split(separator: ".")
        where part.count == 10 && part.allSatisfy({ $0.isUppercase || $0.isNumber }) {
            return String(part)
        }
        return nil
    }

    /// A sandbox container is live when its recorded owner team is installed, or when the
    /// app bundle it records still exists. Missing or unreadable metadata falls back to the
    /// identifier checks already applied by the caller.
    static func containerIsOrphan(_ container: URL, teams: Set<String>) -> Bool {
        let metadata = container.appendingPathComponent(".com.apple.containermanagerd.metadata.plist")
        guard let data = try? Data(contentsOf: metadata),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any],
            let info = plist["MCMMetadataInfo"] as? [String: Any]
        else { return true }
        if let owners = info["Owners"] as? String,
            let payload = owners.data(using: .utf8),
            let list = try? JSONSerialization.jsonObject(with: payload) as? [[String: Any]],
            list.contains(where: { ($0["teamIdentifier"] as? String).map(teams.contains) ?? false })
        {
            return false
        }
        if let validation = info["SandboxProfileDataValidationInfo"] as? [String: Any],
            let parameters = validation["Parameters"] as? [String: Any],
            let bundle = parameters["application_bundle"] as? String,
            FileManager.default.fileExists(atPath: bundle)
        {
            return false
        }
        return true
    }
}
