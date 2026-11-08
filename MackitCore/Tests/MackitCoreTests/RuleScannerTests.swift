import Foundation
import Testing

@testable import MackitCore

struct RuleScannerTests {
    private func rule(_ id: String) throws -> Rule {
        try #require(Rule.catalog.first { $0.id == id })
    }

    private func setMTime(_ url: URL, daysAgo: Double) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-daysAgo * 86_400)], ofItemAtPath: url.path)
    }

    @Test func catalogIDsAreUnique() {
        #expect(Set(Rule.catalog.map(\.id)).count == Rule.catalog.count)
    }

    @Test func cacheChildrenBecomeItems() async throws {
        let dir = try TempDir()
        try dir.file("Library/Caches/a/x", bytes: 5_000_000)
        try dir.file("Library/Caches/b/y", bytes: 3_000_000)
        let result = try await RuleScanner(home: dir.url).scan(try rule("caches"))
        #expect(Set(result.items.map(\.url.lastPathComponent)) == ["a", "b"])
        #expect(result.items.allSatisfy { $0.risk == .safe && $0.mode == .permanent })
        #expect(result.totalBytes > 7_900_000 && result.totalBytes < 8_200_000)
    }

    @Test func cachesSkipDotDSStore() async throws {
        let dir = try TempDir()
        try dir.file("Library/Caches/.DS_Store", bytes: 100)
        try dir.file("Library/Caches/blob/x", bytes: 100)
        let result = try await RuleScanner(home: dir.url).scan(try rule("caches"))
        #expect(result.items.map(\.url.lastPathComponent) == ["blob"])
    }

    @Test func devGarbageFindsProjectBuildDirsOnce() async throws {
        let dir = try TempDir()
        try dir.file("Development/repos/app/node_modules/express/index.js", bytes: 1_000_000)
        // A match is a leaf: nested node_modules are never double-counted.
        try dir.file("Development/repos/app/node_modules/left-pad/index.js", bytes: 100)
        try dir.file("Development/repos/api/target/release/binary", bytes: 2_000_000)
        try dir.file("Documents/site/vendor/autoload.php", bytes: 500_000)
        // .git is never entered, so nothing inside it matches.
        try dir.file("Development/repos/api/.git/node_modules/x", bytes: 100)
        // Files are not matches, and shallow files are not either.
        try dir.file("Development/repos/README.md", bytes: 100)
        let result = try await RuleScanner(home: dir.url).scan(try rule("dev-garbage"))
        let names = Set(result.items.map(\.url.lastPathComponent))
        #expect(names == ["node_modules", "target", "vendor"])
        #expect(result.items.allSatisfy { $0.risk == .review && $0.mode == .trash })
        #expect(result.totalBytes > 3_400_000)
    }

    @Test func devGarbageWithoutProjectsIsEmpty() async throws {
        let dir = try TempDir()
        try dir.file("Development/notes.txt", bytes: 100)
        let result = try await RuleScanner(home: dir.url).scan(try rule("dev-garbage"))
        #expect(result.items.isEmpty)
    }

    @Test func missingRootIsEmptyNotError() async throws {
        let dir = try TempDir()
        let result = try await RuleScanner(home: dir.url).scan(try rule("package-caches"))
        #expect(result.items.isEmpty)
        #expect(!result.needsFullDiskAccess)
    }

    @Test func unreadableRootNeedsFullDiskAccess() async throws {
        let dir = try TempDir()
        try dir.file("Library/Caches/a/x", bytes: 10)
        let caches = dir.url.appendingPathComponent("Library/Caches")
        #expect(chmod(caches.path, 0o000) == 0)
        defer { chmod(caches.path, 0o755) }
        let result = try await RuleScanner(home: dir.url).scan(try rule("caches"))
        #expect(result.needsFullDiskAccess)
        #expect(result.items.isEmpty)
    }

    @Test func installersNeedAgeAndExtension() async throws {
        let dir = try TempDir()
        let old = try dir.file("Downloads/old.dmg", bytes: 1000)
        let recent = try dir.file("Downloads/new.dmg", bytes: 1000)
        let notes = try dir.file("Downloads/notes.txt", bytes: 1000)
        try setMTime(old, daysAgo: 40)
        try setMTime(recent, daysAgo: 10)
        try setMTime(notes, daysAgo: 40)
        let result = try await RuleScanner(home: dir.url).scan(try rule("installers"))
        #expect(result.items.map(\.url.lastPathComponent) == ["old.dmg"])
        #expect(result.items.first?.mode == .trash)
    }

    @Test func logsSkipMackitOwnLog() async throws {
        let dir = try TempDir()
        try dir.file("Library/Logs/Mackit/clean.log", bytes: 100)
        try dir.file("Library/Logs/other/x.log", bytes: 100)
        let result = try await RuleScanner(home: dir.url).scan(try rule("logs"))
        #expect(result.items.map(\.url.lastPathComponent) == ["other"])
    }

    @Test func parentRuleSkipsFoldersClaimedByOtherRules() async throws {
        let dir = try TempDir()
        try dir.file("Library/Caches/Google/Chrome/data", bytes: 100)
        try dir.file("Library/Caches/Homebrew/downloads/pkg", bytes: 100)
        try dir.file("Library/Caches/foo/x", bytes: 100)
        let scanner = RuleScanner(home: dir.url)
        #expect(try await scanner.scan(try rule("caches")).items.map(\.url.lastPathComponent) == ["foo"])
        #expect(try await scanner.scan(try rule("browser-chrome")).items.map(\.url.lastPathComponent) == ["data"])
        #expect(try await scanner.scan(try rule("package-caches")).items.map(\.url.lastPathComponent) == ["Homebrew"])
    }

    @Test func packageCachesAreOneItemPerTool() async throws {
        let dir = try TempDir()
        try dir.file("Library/Caches/go-build/8f/x", bytes: 100)
        try dir.file("Library/Caches/go-build/8a/y", bytes: 100)
        try dir.file("Library/Caches/Homebrew/downloads/z", bytes: 100)
        let items = try await RuleScanner(home: dir.url).scan(try rule("package-caches")).items
        #expect(Set(items.map(\.url.lastPathComponent)) == ["go-build", "Homebrew"])
        #expect(items.allSatisfy { dir.policy.isDeletable($0.url) == .allowed })
    }

    @Test func browserItemsCarryTheirOwnerApp() async throws {
        let dir = try TempDir()
        try dir.file("Library/Caches/Google/Chrome/Profile 4/data", bytes: 100)
        let items = try await RuleScanner(home: dir.url).scan(try rule("browser-chrome")).items
        #expect(items.map(\.url.lastPathComponent) == ["Profile 4"])
        #expect(items.first?.ownerBundleID == "com.google.Chrome")
    }

    @Test func keepNewestKeepsLatestDeviceSupport() async throws {
        let dir = try TempDir()
        try dir.file("Library/Developer/Xcode/iOS DeviceSupport/17.0/x", bytes: 100)
        try dir.file("Library/Developer/Xcode/iOS DeviceSupport/18.0/x", bytes: 100)
        try setMTime(dir.url.appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport/17.0"), daysAgo: 100)
        let result = try await RuleScanner(home: dir.url).scan(try rule("xcode-device-support"))
        #expect(result.items.map(\.url.lastPathComponent) == ["17.0"])
    }

    @Test func scanAllYieldsOneResultPerRule() async throws {
        let dir = try TempDir()
        try dir.file("Library/Caches/a/x", bytes: 100)
        var ids: [String] = []
        for await result in RuleScanner(home: dir.url).scanAll() { ids.append(result.ruleID) }
        #expect(Set(ids) == Set(Rule.catalog.map(\.id)))
    }

    // MARK: - absolute roots

    @Test func absoluteRootResolvesCorrectly() async throws {
        let dir = try TempDir()
        try dir.file("outside/profiles/gen-1/blobs", bytes: 1_000_000)
        try dir.file("outside/profiles/gen-2/blobs", bytes: 2_000_000)
        let rule = Rule(id: "test-abs", title: "Test", roots: [dir.url.appendingPathComponent("outside/profiles").path], risk: .safe, mode: .permanent)
        let result = try await RuleScanner(home: dir.url, rules: [rule]).scan(rule)
        #expect(Set(result.items.map(\.url.lastPathComponent)) == ["gen-1", "gen-2"])
        #expect(result.totalBytes > 2_900_000)
    }

    @Test func absoluteRootWithWholeRootsShowsRootAsItem() async throws {
        let dir = try TempDir()
        try dir.file("outside/nix-profiles/gen-1/blobs", bytes: 1_000_000)
        try dir.file("outside/nix-profiles/gen-2/blobs", bytes: 2_000_000)
        let rule = Rule(id: "test-abs-whole", title: "Test", roots: [dir.url.appendingPathComponent("outside/nix-profiles").path], risk: .review, mode: .trash, wholeRoots: true)
        let result = try await RuleScanner(home: dir.url, rules: [rule]).scan(rule)
        #expect(result.items.map(\.url.lastPathComponent) == ["nix-profiles"])
        #expect(result.totalBytes > 2_900_000)
    }

    @Test func nixRuleIsInCatalog() {
        let nix = Rule.catalog.first { $0.id == "nix" }
        #expect(nix != nil)
        #expect(nix?.roots.first?.hasPrefix("/") == true)
        #expect(nix?.risk == .informational)
        #expect(nix?.wholeRoots == true)
        #expect(nix?.listOnly == true)
    }

    @Test func absoluteRootMissingIsEmptyNotError() async throws {
        let dir = try TempDir()
        let rule = Rule(id: "test-missing", title: "Test", roots: ["/tmp/mackit-nonexistent-\(UUID())"], risk: .safe, mode: .permanent)
        let result = try await RuleScanner(home: dir.url, rules: [rule]).scan(rule)
        #expect(result.items.isEmpty)
        #expect(!result.needsFullDiskAccess)
    }
}
