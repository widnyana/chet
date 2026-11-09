import Foundation
import Testing

@testable import ChetCore

struct AppUninstallerTests {
    @discardableResult
    private func makeApp(
        in folder: URL, name: String, bundleID: String?, version: String = "1.0"
    ) throws -> URL {
        let app = folder.appendingPathComponent("\(name).app")
        let info = app.appendingPathComponent("Contents/Info.plist")
        try FileManager.default.createDirectory(
            at: info.deletingLastPathComponent(), withIntermediateDirectories: true)
        var values: [String: Any] = [
            "CFBundleName": name, "CFBundlePackageType": "APPL", "CFBundleShortVersionString": version,
        ]
        if let bundleID { values["CFBundleIdentifier"] = bundleID }
        try (values as NSDictionary).write(to: info)
        try Data(repeating: 1, count: 100).write(to: app.appendingPathComponent("Contents/App"))
        return app
    }

    private func uninstaller(
        home: URL, apps: [URL], roots: [AppSearchRoot], running: Bool = false,
        trash: @escaping @Sendable (URL) throws -> Void = { _ in },
        privileged: (@Sendable (URL, String) -> UninstallOutcome?)? = nil
    ) -> AppUninstaller {
        AppUninstaller(
            home: home, appFolders: apps, searchRoots: roots, log: nil, recorder: nil,
            isRunning: { _ in running }, trash: trash, privileged: privileged)
    }

    @Test func discoversAppsIncludingOneNestedFolderAndDeduplicates() throws {
        let home = try TempDir()
        let apps = try TempDir()
        try makeApp(in: apps.url, name: "Foobar", bundleID: "com.test.foobar")
        let nested = apps.url.appendingPathComponent("Utilities")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try makeApp(in: nested, name: "Bazqux", bundleID: "com.test.bazqux")
        try makeApp(in: apps.url, name: "FoobarCopy", bundleID: "com.test.foobar")

        let found = AppUninstaller(home: home.url, appFolders: [apps.url], searchRoots: [])
            .installedApps()
        #expect(found.map(\.name) == ["Bazqux", "Foobar"])
        #expect(found.first { $0.name == "Foobar" }?.url.lastPathComponent == "Foobar.app")
    }

    @Test func readsHelpersAndVendor() throws {
        let home = try TempDir()
        let apps = try TempDir()
        let app = try makeApp(in: apps.url, name: "Foobar", bundleID: "com.test.foobar")
        let helper = app.appendingPathComponent("Contents/Frameworks/Foobar Helper.app")
        try FileManager.default.createDirectory(
            at: helper.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let info: NSDictionary = ["CFBundleIdentifier": "com.test.foobar.helper"]
        try info.write(to: helper.appendingPathComponent("Contents/Info.plist"))

        let found = AppUninstaller(home: home.url, appFolders: [apps.url], searchRoots: [])
            .installedApps()
        #expect(found.count == 1)
        #expect(found[0].helperBundleIDs == ["com.test.foobar.helper"])
        #expect(found[0].vendorLabel == "test")
    }

    @Test(arguments: [
        ("com.test.foobar.plist", "com.test.foobar"),
        ("com.test.foobar.savedState", "com.test.foobar"),
        ("com.test.foobar.binarycookies", "com.test.foobar"),
        ("group.com.test.shared", "com.test.shared"),
        ("ABCDE12345.com.test.shared", "com.test.shared"),
        ("com.test.foobar.123E4567-E89B-12D3-A456-426614174000.plist", "com.test.foobar"),
    ])
    func normalizesIdentifiers(name: String, expected: String) {
        #expect(AppUninstaller.normalizedIdentifier(name) == expected)
    }

    @Test(arguments: ["Google", ".GlobalPreferences.plist", "com.test", "a..b.c"])
    func rejectsNonIdentifiers(name: String) {
        #expect(AppUninstaller.normalizedIdentifier(name) == nil)
    }

    @Test func matchesExactBundleIDHelperAndBoundary() async throws {
        let home = try TempDir()
        let apps = try TempDir()
        try makeApp(in: apps.url, name: "Foobar", bundleID: "com.test.foobar")
        try home.file("Library/Preferences/com.test.foobar.plist", bytes: 10)
        try home.file("Library/Preferences/com.test.foobar.helper.plist", bytes: 20)
        try home.file("Library/Preferences/com.test.foobar2.plist", bytes: 30)
        try home.file("Library/Preferences/com.other.app.plist", bytes: 40)

        let app = try #require(
            AppUninstaller(home: home.url, appFolders: [apps.url], searchRoots: []).installedApps().first)
        let roots = [
            AppSearchRoot(url: home.url.appendingPathComponent("Library/Preferences"), kind: .preferences, maxDepth: 0)
        ]
        let components = await uninstaller(home: home.url, apps: [apps.url], roots: roots)
            .components(for: app, installedApps: [app])
        let names = Set(components.map(\.url.lastPathComponent))
        #expect(names == ["com.test.foobar.plist", "com.test.foobar.helper.plist"])
        #expect(components.allSatisfy { $0.ownership == .exclusive })
        #expect(components.allSatisfy { $0.defaultSelected })
    }

    @Test func findsNestedVendorFolderWithoutSelectingTheVendor() async throws {
        let home = try TempDir()
        let apps = try TempDir()
        try makeApp(in: apps.url, name: "Google Chrome", bundleID: "com.google.Chrome")
        try home.file("Library/Application Support/Google/Chrome/Default/History", bytes: 500)
        try home.file("Library/Application Support/Google/Drive/data", bytes: 500)
        try home.file("Library/Application Support/Other/Chrome/data", bytes: 500)

        let app = try #require(
            AppUninstaller(home: home.url, appFolders: [apps.url], searchRoots: []).installedApps().first)
        let roots = [
            AppSearchRoot(
                url: home.url.appendingPathComponent("Library/Application Support"), kind: .applicationSupport,
                maxDepth: 2)
        ]
        let components = await uninstaller(home: home.url, apps: [apps.url], roots: roots)
            .components(for: app, installedApps: [app])
        #expect(components.count == 1)
        let found = try #require(components.first)
        #expect(found.url.lastPathComponent == "Chrome")
        #expect(found.ownership == .probable)
        #expect(found.match == .nestedName)
        #expect(!found.defaultSelected)
        #expect(found.isSelectable)
        #expect(found.bytes >= 500)
    }

    @Test func groupContainersAreSharedAndUnselectable() async throws {
        let home = try TempDir()
        let apps = try TempDir()
        try makeApp(in: apps.url, name: "Foobar", bundleID: "com.test.foobar")
        try home.file("Library/Group Containers/group.com.test.foobar/data", bytes: 10)

        let app = try #require(
            AppUninstaller(home: home.url, appFolders: [apps.url], searchRoots: []).installedApps().first)
        let roots = [
            AppSearchRoot(
                url: home.url.appendingPathComponent("Library/Group Containers"), kind: .groupContainers, maxDepth: 0)
        ]
        let component = try #require(
            await uninstaller(home: home.url, apps: [apps.url], roots: roots)
                .components(for: app, installedApps: [app]).first)
        #expect(component.ownership == .shared)
        #expect(!component.isSelectable)
        #expect(!component.defaultSelected)
    }

    @Test func dataClaimedByAnotherInstalledAppIsShared() async throws {
        let home = try TempDir()
        let apps = try TempDir()
        try makeApp(in: apps.url, name: "Foobar", bundleID: "com.test.foobar")
        try makeApp(in: apps.url, name: "Sharedthing", bundleID: "com.test.foobar.shared")
        try home.file("Library/Caches/com.test.foobar.shared/data", bytes: 10)

        let inventory = AppUninstaller(home: home.url, appFolders: [apps.url], searchRoots: []).installedApps()
        let app = try #require(inventory.first { $0.bundleID == "com.test.foobar" })
        let roots = [
            AppSearchRoot(url: home.url.appendingPathComponent("Library/Caches"), kind: .caches, maxDepth: 0)
        ]
        let component = try #require(
            await uninstaller(home: home.url, apps: [apps.url], roots: roots)
                .components(for: app, installedApps: inventory).first)
        #expect(component.ownership == .shared)
        #expect(!component.isSelectable)
    }

    @Test func genericAndShortNamesNeverMatch() {
        let app = InstalledApp(
            url: URL(fileURLWithPath: "/Applications/Data.app"), name: "Data", bundleID: "com.test.data",
            version: nil, helperBundleIDs: [], vendorLabel: "test", isWritable: true,
            stamp: FileStamp(
                inode: 1, size: 0, modified: Date(), links: 1, isSymlink: false, isRegularFile: false,
                isDataless: false))
        #expect(
            AppUninstaller.matchName(
                "Data", kind: .applicationSupport, depth: 0, app: app, otherIDs: [], otherNames: [])
                == nil)
        let short = InstalledApp(
            url: URL(fileURLWithPath: "/Applications/Arc.app"), name: "Arc", bundleID: "com.test.arc",
            version: nil, helperBundleIDs: [], vendorLabel: "test", isWritable: true,
            stamp: FileStamp(
                inode: 1, size: 0, modified: Date(), links: 1, isSymlink: false, isRegularFile: false,
                isDataless: false))
        #expect(
            AppUninstaller.matchName(
                "Arc", kind: .applicationSupport, depth: 0, app: short, otherIDs: [], otherNames: [])
                == nil)
    }

    @Test func vendorFolderIsNotANameMatch() {
        let app = InstalledApp(
            url: URL(fileURLWithPath: "/Applications/Strings.app"), name: "Strings", bundleID: "com.google.Strings",
            version: nil, helperBundleIDs: [], vendorLabel: "google", isWritable: true,
            stamp: FileStamp(
                inode: 1, size: 0, modified: Date(), links: 1, isSymlink: false, isRegularFile: false,
                isDataless: false))
        #expect(
            AppUninstaller.matchName(
                "Google", kind: .applicationSupport, depth: 0, app: app, otherIDs: [], otherNames: [])
                == nil)
    }

    @Test func protectedAndPrivilegedLocationsAreNeverSelected() async throws {
        let home = try TempDir()
        let apps = try TempDir()
        try makeApp(in: apps.url, name: "Foobar", bundleID: "com.test.foobar")
        try home.file("Library/Keychains/com.test.foobar/key", bytes: 10)
        try home.file("Library/Preferences/com.test.foobar.plist", bytes: 10)

        let app = try #require(
            AppUninstaller(home: home.url, appFolders: [apps.url], searchRoots: []).installedApps().first)
        let roots = [
            AppSearchRoot(url: home.url.appendingPathComponent("Library/Keychains"), kind: .preferences, maxDepth: 0),
            AppSearchRoot(
                url: home.url.appendingPathComponent("Library/Preferences"), kind: .preferences, maxDepth: 0),
        ]
        let components = await uninstaller(home: home.url, apps: [apps.url], roots: roots)
            .components(for: app, installedApps: [app])
        let protected = try #require(components.first { $0.url.lastPathComponent == "com.test.foobar" })
        #expect(protected.ownership == .systemProtected)
        #expect(!protected.isSelectable)
        let normal = try #require(components.first { $0.url.pathExtension == "plist" })
        #expect(normal.ownership == .exclusive)
        #expect(normal.defaultSelected)
    }

    @Test func privilegedRootsAreAdministratorOnly() async throws {
        let home = try TempDir()
        let apps = try TempDir()
        try makeApp(in: apps.url, name: "Foobar", bundleID: "com.test.foobar")
        try home.file("Library/LaunchDaemons/com.test.foobar.plist", bytes: 10)

        let app = try #require(
            AppUninstaller(home: home.url, appFolders: [apps.url], searchRoots: []).installedApps().first)
        let roots = [
            AppSearchRoot(
                url: home.url.appendingPathComponent("Library/LaunchDaemons"), kind: .launchAgents,
                maxDepth: 0, requiresAdmin: true)
        ]
        let component = try #require(
            await uninstaller(home: home.url, apps: [apps.url], roots: roots)
                .components(for: app, installedApps: [app]).first)
        #expect(component.ownership == .privileged)
        #expect(component.requiresAdmin)
        #expect(!component.isSelectable)
        #expect(!component.defaultSelected)
    }

    @Test func adminRemnantIsHandedToTheHelper() async throws {
        let (home, apps, app, roots, component) = try await adminFixture()

        let ids = BundleIDs()
        let plan = UninstallPlan(
            app: app, components: [component], includeApp: false, appBytes: 0,
            otherBundleIDs: [], otherNames: [])
        let report = await uninstaller(
            home: home.url, apps: [apps.url], roots: roots,
            privileged: { _, bundleID in
                ids.append(bundleID)
                return .removed(component.bytes)
            }
        )
        .uninstall(plan, dryRun: false)

        #expect(report.results.first?.outcome == .removed(component.bytes))
        #expect(report.removedBytes == component.bytes)
        #expect(report.removedCount == 1)
        #expect(report.trashedBytes == 0)
        #expect(ids.value == ["com.test.foobar"])
    }

    @Test func adminRemnantWithoutHelperIsSkipped() async throws {
        let (home, apps, app, roots, component) = try await adminFixture()

        let plan = UninstallPlan(
            app: app, components: [component], includeApp: false, appBytes: 0,
            otherBundleIDs: [], otherNames: [])
        let report = await uninstaller(home: home.url, apps: [apps.url], roots: roots)
            .uninstall(plan, dryRun: false)
        #expect(report.results.first?.outcome == .skipped(.requiresAdmin))
        #expect(report.removedBytes == 0)
    }

    @Test func adminRemnantUnderDryRunNeverCallsTheHelper() async throws {
        let (home, apps, app, roots, component) = try await adminFixture()

        let calls = Counter()
        let plan = UninstallPlan(
            app: app, components: [component], includeApp: false, appBytes: 0,
            otherBundleIDs: [], otherNames: [])
        let report = await uninstaller(
            home: home.url, apps: [apps.url], roots: roots,
            privileged: { _, _ in
                calls.increment()
                return .removed(component.bytes)
            }
        )
        .uninstall(plan, dryRun: true)

        #expect(calls.value == 0)
        #expect(report.results.first?.outcome == .removed(component.bytes))
        #expect(report.results.first?.dryRun == true)
    }

    /// A launch daemon under a root-owned search root: a real admin remnant, in a temp home.
    private func adminFixture() async throws -> (
        home: TempDir, apps: TempDir, app: InstalledApp, roots: [AppSearchRoot], component: AppComponent
    ) {
        let home = try TempDir()
        let apps = try TempDir()
        try makeApp(in: apps.url, name: "Foobar", bundleID: "com.test.foobar")
        try home.file("Library/LaunchDaemons/com.test.foobar.plist", bytes: 10)
        let app = try #require(
            AppUninstaller(home: home.url, appFolders: [apps.url], searchRoots: []).installedApps().first)
        let roots = [
            AppSearchRoot(
                url: home.url.appendingPathComponent("Library/LaunchDaemons"), kind: .launchDaemons,
                maxDepth: 0, requiresAdmin: true)
        ]
        let component = try #require(
            await uninstaller(home: home.url, apps: [apps.url], roots: roots)
                .components(for: app, installedApps: [app]).first)
        #expect(component.requiresAdmin)
        return (home, apps, app, roots, component)
    }

    @Test func launchAgentMatchesLabelAndAssociatedIdentifiers() async throws {
        let home = try TempDir()
        let apps = try TempDir()
        try makeApp(in: apps.url, name: "Foobar", bundleID: "com.test.foobar")
        let agents = home.url.appendingPathComponent("Library/LaunchAgents")
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        let byLabel: NSDictionary = ["Label": "com.test.foobar.agent"]
        try byLabel.write(to: agents.appendingPathComponent("random-name.plist"))
        let byAssociation: NSDictionary = [
            "Label": "com.example.other", "AssociatedBundleIdentifiers": ["com.test.foobar"],
        ]
        try byAssociation.write(to: agents.appendingPathComponent("other.plist"))
        let unrelated: NSDictionary = ["Label": "com.nope.agent"]
        try unrelated.write(to: agents.appendingPathComponent("nope.plist"))

        let app = try #require(
            AppUninstaller(home: home.url, appFolders: [apps.url], searchRoots: []).installedApps().first)
        let roots = [AppSearchRoot(url: agents, kind: .launchAgents, maxDepth: 0)]
        let components = await uninstaller(home: home.url, apps: [apps.url], roots: roots)
            .components(for: app, installedApps: [app])
        #expect(Set(components.map(\.url.lastPathComponent)) == ["random-name.plist", "other.plist"])
        #expect(components.allSatisfy { $0.ownership == .exclusive })
    }

    @Test func byHostPreferencesMatchDespiteUUID() async throws {
        let home = try TempDir()
        let apps = try TempDir()
        try makeApp(in: apps.url, name: "Foobar", bundleID: "com.test.foobar")
        try home.file(
            "Library/Preferences/ByHost/com.test.foobar.123E4567-E89B-12D3-A456-426614174000.plist", bytes: 10)

        let app = try #require(
            AppUninstaller(home: home.url, appFolders: [apps.url], searchRoots: []).installedApps().first)
        let roots = [
            AppSearchRoot(
                url: home.url.appendingPathComponent("Library/Preferences/ByHost"), kind: .preferences, maxDepth: 0)
        ]
        let components = await uninstaller(home: home.url, apps: [apps.url], roots: roots)
            .components(for: app, installedApps: [app])
        #expect(components.count == 1)
        #expect(components[0].ownership == .exclusive)
    }

    @Test func sharedComponentIsSkippedEvenWhenThePlanIncludesIt() async throws {
        let home = try TempDir()
        let apps = try TempDir()
        try makeApp(in: apps.url, name: "Foobar", bundleID: "com.test.foobar")
        try makeApp(in: apps.url, name: "Sharedthing", bundleID: "com.test.foobar.shared")
        try home.file("Library/Caches/com.test.foobar.shared/data", bytes: 10)

        let inventory = AppUninstaller(home: home.url, appFolders: [apps.url], searchRoots: []).installedApps()
        let app = try #require(inventory.first { $0.bundleID == "com.test.foobar" })
        let roots = [
            AppSearchRoot(url: home.url.appendingPathComponent("Library/Caches"), kind: .caches, maxDepth: 0)
        ]
        let component = try #require(
            await uninstaller(home: home.url, apps: [apps.url], roots: roots)
                .components(for: app, installedApps: inventory).first)
        #expect(!component.isSelectable)

        let counter = Counter()
        let plan = UninstallPlan(
            app: app, components: [component], includeApp: false, appBytes: 0,
            otherBundleIDs: Set(inventory.flatMap(\.allBundleIDs)),
            otherNames: Set(inventory.map { $0.name.lowercased() }))
        let report = await uninstaller(
            home: home.url, apps: [apps.url], roots: roots, trash: { _ in counter.increment() }
        )
        .uninstall(plan, dryRun: false)
        #expect(counter.value == 0)
        #expect(report.results.first { $0.kind != .application }?.outcome == .skipped(.shared))
    }

    @Test func protectsSystemAndPrivatePaths() throws {
        let home = try TempDir()
        let policy = SafetyPolicy(home: home.url)
        #expect(policy.isProtectedPath(URL(fileURLWithPath: "/System/Library")))
        #expect(policy.isProtectedPath(URL(fileURLWithPath: "/private/etc/hosts")))
        #expect(policy.isProtectedPath(home.url.appendingPathComponent("Library/Keychains/x")))
        #expect(!policy.isProtectedPath(home.url.appendingPathComponent("Library/Caches/com.test.foo")))
    }

    @Test func dryRunNeverCallsTrash() async throws {
        let home = try TempDir()
        let apps = try TempDir()
        try makeApp(in: apps.url, name: "Foobar", bundleID: "com.test.foobar")
        try home.file("Library/Preferences/com.test.foobar.plist", bytes: 10)

        let app = try #require(
            AppUninstaller(home: home.url, appFolders: [apps.url], searchRoots: []).installedApps().first)
        let roots = [
            AppSearchRoot(
                url: home.url.appendingPathComponent("Library/Preferences"), kind: .preferences, maxDepth: 0)
        ]
        let components = await uninstaller(home: home.url, apps: [apps.url], roots: roots)
            .components(for: app, installedApps: [app])
        let counter = Counter()
        let plan = UninstallPlan(
            app: app, components: components, includeApp: true, appBytes: 100,
            otherBundleIDs: [], otherNames: [])
        let worker = uninstaller(
            home: home.url, apps: [apps.url], roots: roots,
            trash: { _ in counter.increment() })
        let report = await worker.uninstall(plan, dryRun: true)
        #expect(counter.value == 0)
        #expect(report.dryRun)
        #expect(report.results.count == 2)
        #expect(report.trashedBytes == 4196)
        #expect(report.results.allSatisfy { $0.dryRun })
    }

    @Test func changedComponentIsSkipped() async throws {
        let home = try TempDir()
        let apps = try TempDir()
        try makeApp(in: apps.url, name: "Foobar", bundleID: "com.test.foobar")
        let file = try home.file("Library/Preferences/com.test.foobar.plist", bytes: 10)

        let app = try #require(
            AppUninstaller(home: home.url, appFolders: [apps.url], searchRoots: []).installedApps().first)
        let roots = [
            AppSearchRoot(
                url: home.url.appendingPathComponent("Library/Preferences"), kind: .preferences, maxDepth: 0)
        ]
        let components = await uninstaller(home: home.url, apps: [apps.url], roots: roots)
            .components(for: app, installedApps: [app])
        try Data(repeating: 2, count: 200).write(to: file)

        let counter = Counter()
        let plan = UninstallPlan(
            app: app, components: components, includeApp: false, appBytes: 0,
            otherBundleIDs: [], otherNames: [])
        let report = await uninstaller(
            home: home.url, apps: [apps.url], roots: roots, trash: { _ in counter.increment() }
        )
        .uninstall(plan, dryRun: false)
        #expect(counter.value == 0)
        #expect(report.results.contains { $0.outcome == .skipped(.changed) })
    }

    @Test func runningAppRefusesEverything() async throws {
        let home = try TempDir()
        let apps = try TempDir()
        try makeApp(in: apps.url, name: "Foobar", bundleID: "com.test.foobar")
        try home.file("Library/Preferences/com.test.foobar.plist", bytes: 10)
        let app = try #require(
            AppUninstaller(home: home.url, appFolders: [apps.url], searchRoots: []).installedApps().first)
        let roots = [
            AppSearchRoot(
                url: home.url.appendingPathComponent("Library/Preferences"), kind: .preferences, maxDepth: 0)
        ]
        let components = await uninstaller(home: home.url, apps: [apps.url], roots: roots)
            .components(for: app, installedApps: [app])
        let counter = Counter()
        let plan = UninstallPlan(
            app: app, components: components, includeApp: true, appBytes: 100,
            otherBundleIDs: [], otherNames: [])
        let report = await uninstaller(
            home: home.url, apps: [apps.url], roots: roots, running: true,
            trash: { _ in counter.increment() }
        )
        .uninstall(plan, dryRun: false)
        #expect(counter.value == 0)
        #expect(report.results.count == 2)
        #expect(report.results.allSatisfy { $0.outcome == .skipped(.appRunning) })
    }

    @Test func appBundleIsMovedLast() async throws {
        let home = try TempDir()
        let apps = try TempDir()
        let appURL = try makeApp(in: apps.url, name: "Foobar", bundleID: "com.test.foobar")
        try home.file("Library/Preferences/com.test.foobar.plist", bytes: 10)
        let app = try #require(
            AppUninstaller(home: home.url, appFolders: [apps.url], searchRoots: []).installedApps().first)
        let roots = [
            AppSearchRoot(
                url: home.url.appendingPathComponent("Library/Preferences"), kind: .preferences, maxDepth: 0)
        ]
        let components = await uninstaller(home: home.url, apps: [apps.url], roots: roots)
            .components(for: app, installedApps: [app])
        let paths = Paths()
        let plan = UninstallPlan(
            app: app, components: components, includeApp: true, appBytes: 100,
            otherBundleIDs: [], otherNames: [])
        let report = await uninstaller(
            home: home.url, apps: [apps.url], roots: roots, trash: { paths.append($0) }
        )
        .uninstall(plan, dryRun: false)
        #expect(AppUninstaller.canonicalPath(try #require(paths.value.last)) == AppUninstaller.canonicalPath(appURL))
        #expect(paths.value.count == 2)
        #expect(report.trashedBytes == 4196)
    }

    @Test func appOutsideAppFoldersIsRefused() async throws {
        let home = try TempDir()
        let apps = try TempDir()
        try makeApp(in: apps.url, name: "Foobar", bundleID: "com.test.foobar")
        let app = try #require(
            AppUninstaller(home: home.url, appFolders: [apps.url], searchRoots: []).installedApps().first)
        let counter = Counter()
        let plan = UninstallPlan(
            app: app, components: [], includeApp: true, appBytes: 100,
            otherBundleIDs: [], otherNames: [])
        let report = await AppUninstaller(
            home: home.url, appFolders: [], searchRoots: [], log: nil, recorder: nil,
            isRunning: { _ in false }, trash: { _ in counter.increment() }
        )
        .uninstall(plan, dryRun: false)
        #expect(counter.value == 0)
        #expect(report.results.first?.outcome == .skipped(.policy))
    }

    @Test func uninstallRowsReachTheAuditLog() async throws {
        let home = try TempDir()
        let apps = try TempDir()
        try makeApp(in: apps.url, name: "Foobar", bundleID: "com.test.foobar")
        try home.file("Library/Preferences/com.test.foobar.plist", bytes: 10)
        let app = try #require(
            AppUninstaller(home: home.url, appFolders: [apps.url], searchRoots: []).installedApps().first)
        let roots = [
            AppSearchRoot(
                url: home.url.appendingPathComponent("Library/Preferences"), kind: .preferences, maxDepth: 0)
        ]
        let logURL = home.url.appendingPathComponent("Library/Logs/chet/clean.log")
        let worker = AppUninstaller(
            home: home.url, appFolders: [apps.url], searchRoots: roots, log: AuditLog(url: logURL),
            recorder: nil, isRunning: { _ in false }, trash: { _ in })
        let components = await worker.components(for: app, installedApps: [app])
        let report = await worker.uninstall(
            UninstallPlan(
                app: app, components: components, includeApp: true, appBytes: 100,
                otherBundleIDs: [], otherNames: []),
            dryRun: false)
        #expect(report.trashedCount == 2)
        let lines = try String(contentsOf: logURL, encoding: .utf8)
            .split(separator: "\n").compactMap { line -> [String: Any]? in
                (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
            }
        #expect(lines.count == 2)
        #expect(lines.allSatisfy { $0["result"] as? String == "trashed" })
        #expect(lines.allSatisfy { $0["mode"] as? String == "trash" })
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

private final class Paths: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [URL] = []

    var value: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return paths
    }

    func append(_ url: URL) {
        lock.lock()
        paths.append(url)
        lock.unlock()
    }
}

private final class BundleIDs: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [String] = []

    var value: [String] {
        lock.lock()
        defer { lock.unlock() }
        return ids
    }

    func append(_ id: String) {
        lock.lock()
        ids.append(id)
        lock.unlock()
    }
}
