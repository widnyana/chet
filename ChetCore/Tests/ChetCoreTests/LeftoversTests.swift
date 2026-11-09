import Foundation
import Testing

@testable import ChetCore

struct LeftoversTests {
    private func app(_ id: String) -> InstalledApp {
        InstalledApp(
            url: URL(fileURLWithPath: "/Applications/\(id).app"), name: id, bundleID: id,
            version: nil, helperBundleIDs: [], vendorLabel: nil, isWritable: true,
            stamp: FileStamp(
                inode: 0, size: 0, modified: Date(), links: 1, isSymlink: false,
                isRegularFile: false, isDataless: false))
    }

    private func scanner(
        _ dir: TempDir, apps: [InstalledApp] = [], teams: Set<String> = [],
        minAge: TimeInterval = 0,
        resolves: @escaping @Sendable (String) -> Bool = { _ in false }
    ) -> LeftoverScanner {
        LeftoverScanner(
            home: dir.url, apps: apps, teamIDs: teams, minAge: minAge, resolvesInstalled: resolves)
    }

    private func names(_ scanner: LeftoverScanner) throws -> Set<String> {
        Set(try scanner.scan().map(\.url.lastPathComponent))
    }

    private func age(_ url: URL, days: Double) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-days * 86_400)], ofItemAtPath: url.path)
    }

    @Test func flagsOnlyOrphanedBundleIDs() throws {
        let dir = try TempDir()
        try dir.file("Library/Preferences/com.gone.app.plist", bytes: 100)
        try dir.file("Library/Preferences/com.apple.finder.plist", bytes: 100)
        try dir.file("Library/Preferences/com.installed.app.plist", bytes: 100)
        try dir.file("Library/Preferences/com.installed.helper.plist", bytes: 100)
        try dir.file("Library/Application Support/Google/x", bytes: 100)
        try dir.file("Library/Application Support/Steam/x", bytes: 100)
        try dir.file("Library/Containers/com.gone.other/x", bytes: 100)
        let names = try names(scanner(dir, apps: [app("com.installed.app")]))
        #expect(names == ["com.gone.app.plist", "com.gone.other"])
    }

    @Test(arguments: [
        ("com.foo.app.plist", "com.foo.app"),
        ("group.com.foo.shared", "com.foo.shared"),
        ("groups.com.foo.shared", "com.foo.shared"),
        ("systemgroup.com.apple.foo.bar.plist", "com.apple.foo.bar"),
        ("ABCDE12345.com.foo.shared", "com.foo.shared"),
        ("ABCDE12345.group.com.foo.shared", "com.foo.shared"),
        ("group.ABCDE12345.com.foo.shared", "com.foo.shared"),
        ("com.foo.app.savedState", "com.foo.app"),
        ("com.foo.app.123E4567-E89B-12D3-A456-426614174000.plist", "com.foo.app"),
    ])
    func parsesBundleIDs(name: String, expected: String) {
        #expect(LeftoverScanner.bundleID(fromName: name) == expected)
    }

    @Test(arguments: [
        "Google", "Steam", ".GlobalPreferences.plist", "com.foo", "a..b.c", "HUAQ24HBR6.dev.orbstack",
    ])
    func rejectsNonBundleNames(name: String) {
        #expect(LeftoverScanner.bundleID(fromName: name) == nil)
    }

    @Test func installedChildAndParentIdentifiersAreLive() throws {
        let dir = try TempDir()
        try dir.file("Library/Preferences/com.test.foo.helper.plist", bytes: 100)
        try dir.file("Library/Saved Application State/com.test.foo.savedState/data.data", bytes: 100)
        #expect(try scanner(dir, apps: [app("com.test.foo")]).scan().isEmpty)
    }

    @Test func launchServicesResolutionKeepsAnInstalledApp() throws {
        let dir = try TempDir()
        try dir.file("Library/Preferences/com.logitech.logiaipromptbuilder.plist", bytes: 100)
        let resolved = scanner(
            dir, resolves: { $0 == "com.logitech.logiaipromptbuilder" })
        #expect(try resolved.scan().isEmpty)
    }

    @Test func appleIdentifiersAreNeverListed() throws {
        let dir = try TempDir()
        try dir.file(
            "Library/Preferences/systemgroup.com.apple.icloud.searchpartyd.sharedsettings.plist", bytes: 100)
        try dir.file("Library/Group Containers/group.com.apple.podcasts/data", bytes: 100)
        try dir.file("Library/Group Containers/group.is.workflow.shortcuts/data", bytes: 100)
        #expect(try scanner(dir, apps: [app("com.test.live")]).scan().isEmpty)
    }

    @Test func groupContainerWithInstalledTeamIsLive() throws {
        let dir = try TempDir()
        try dir.file("Library/Group Containers/EQHXZ8M8AV.group.com.gone.app/data", bytes: 100)
        #expect(try scanner(dir, apps: [app("com.test.live")], teams: ["EQHXZ8M8AV"]).scan().isEmpty)
        let listed = try scanner(dir, apps: [app("com.test.live")]).scan()
        #expect(
            listed.compactMap { LeftoverScanner.bundleID(fromName: $0.url.lastPathComponent) } == [
                "com.gone.app"
            ])
    }

    @Test func containerWithInstalledOwnerTeamIsLive() throws {
        let dir = try TempDir()
        let container = dir.url.appendingPathComponent("Library/Containers/com.gone.app")
        try dir.file("Library/Containers/com.gone.app/Data/x", bytes: 100)
        let metadata: [String: Any] = [
            "MCMMetadataInfo": [
                "Owners": """
                [{"teamIdentifier":"TEAM123456","signingIdentifier":"com.gone.app"}]
                """
            ]
        ]
        try PropertyListSerialization.data(fromPropertyList: metadata, format: .binary, options: 0)
            .write(to: container.appendingPathComponent(".com.apple.containermanagerd.metadata.plist"))
        #expect(try scanner(dir, apps: [app("com.test.live")], teams: ["TEAM123456"]).scan().isEmpty)
        #expect(
            try names(scanner(dir, apps: [app("com.test.live")])) == ["com.gone.app"])
    }

    @Test func recentDataIsNotListedUntilItIsOld() throws {
        let dir = try TempDir()
        let preference = try dir.file("Library/Preferences/com.gone.app.plist", bytes: 100)
        let support = try dir.file("Library/Application Support/com.gone.app/x", bytes: 100)
        let fresh = LeftoverScanner(home: dir.url, apps: [app("com.test.live")], teamIDs: [])
        #expect(try fresh.scan().isEmpty)
        try age(preference, days: 200)
        try age(support.deletingLastPathComponent(), days: 200)
        #expect(try names(fresh) == ["com.gone.app.plist", "com.gone.app"])
    }

    @Test func ownIdentifiersAreNeverListed() throws {
        let dir = try TempDir()
        try dir.file("Library/Preferences/id.web.widnyana.chet.plist", bytes: 100)
        try dir.file(
            "Library/Preferences/com.chet.tweaks.tests.123E4567-E89B-12D3-A456-426614174000.plist",
            bytes: 100)
        #expect(try scanner(dir, apps: [app("com.test.live")]).scan().isEmpty)
    }

    @Test func unreadableAppInventoryListsNothing() throws {
        let dir = try TempDir()
        let preference = try dir.file("Library/Preferences/com.gone.app.plist", bytes: 100)
        try age(preference, days: 200)
        let blind = LeftoverScanner(
            home: dir.url, appFolders: [dir.url.appendingPathComponent("does-not-exist")], minAge: 0)
        #expect(try blind.scan().isEmpty)
    }
}
