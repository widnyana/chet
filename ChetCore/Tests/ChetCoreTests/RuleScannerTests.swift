import Foundation
import Testing

@testable import ChetCore

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

    @Test func devGarbageOffersPythonVirtualEnvironments() async throws {
        let dir = try TempDir()
        try dir.file("Development/repos/app/.venv-codegen/pyvenv.cfg", bytes: 100)
        try dir.file("Development/repos/app/.venv-codegen/lib/python3.14/site-packages/x.py", bytes: 900_000)
        try dir.file("Development/repos/api/venv/pyvenv.cfg", bytes: 100)
        try dir.file("Development/repos/api/venv/bin/python", bytes: 500_000)
        // Only the environment's own bootstrapper writes pyvenv.cfg: a folder that merely
        // carries the name is not an environment.
        try dir.file("Development/repos/other/.venv/notes.txt", bytes: 100)
        let items = try await RuleScanner(home: dir.url).scan(try rule("dev-garbage")).items
        #expect(
            Set(items.map(\.url.path)) == [
                dir.url.appendingPathComponent("Development/repos/app/.venv-codegen").path,
                dir.url.appendingPathComponent("Development/repos/api/venv").path,
            ])
        #expect(items.allSatisfy { $0.risk == .review && $0.mode == .trash })
        #expect(try await RuleScanner(home: dir.url).scan(try rule("terraform-build-dirs")).items.isEmpty)
    }

    @Test func devGarbageWithoutProjectsIsEmpty() async throws {
        let dir = try TempDir()
        try dir.file("Development/notes.txt", bytes: 100)
        let result = try await RuleScanner(home: dir.url).scan(try rule("dev-garbage"))
        #expect(result.items.isEmpty)
    }

    @Test func adminRuleMarksItemsAsAdmin() async throws {
        let dir = try TempDir()
        let root = dir.url.appendingPathComponent("Library/Caches")
        try dir.file("Library/Caches/system/blob/x", bytes: 5_000_000)
        let rule = Rule(
            id: "system-caches-test", title: "System caches", roots: [root.path],
            risk: .review, mode: .permanent, requiresAdmin: true)
        let result = try await RuleScanner(home: dir.url, rules: [rule]).scan(rule)
        #expect(result.items.map(\.url.lastPathComponent) == ["system"])
        #expect(result.items.allSatisfy { $0.requiresAdmin })
        #expect(result.items.allSatisfy { $0.risk == .review && $0.mode == .permanent })
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

    @Test func logsSkipchetOwnLog() async throws {
        let dir = try TempDir()
        try dir.file("Library/Logs/chet/clean.log", bytes: 100)
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
        let rule = Rule(
            id: "test-abs", title: "Test", roots: [dir.url.appendingPathComponent("outside/profiles").path],
            risk: .safe, mode: .permanent)
        let result = try await RuleScanner(home: dir.url, rules: [rule]).scan(rule)
        #expect(Set(result.items.map(\.url.lastPathComponent)) == ["gen-1", "gen-2"])
        #expect(result.totalBytes > 2_900_000)
    }

    @Test func absoluteRootWithWholeRootsShowsRootAsItem() async throws {
        let dir = try TempDir()
        try dir.file("outside/nix-profiles/gen-1/blobs", bytes: 1_000_000)
        try dir.file("outside/nix-profiles/gen-2/blobs", bytes: 2_000_000)
        let rule = Rule(
            id: "test-abs-whole", title: "Test", roots: [dir.url.appendingPathComponent("outside/nix-profiles").path],
            risk: .review, mode: .trash, wholeRoots: true)
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
        let rule = Rule(
            id: "test-missing", title: "Test", roots: ["/tmp/chet-nonexistent-\(UUID())"], risk: .safe, mode: .permanent
        )
        let result = try await RuleScanner(home: dir.url, rules: [rule]).scan(rule)
        #expect(result.items.isEmpty)
        #expect(!result.needsFullDiskAccess)
    }

    // MARK: - tool state sub-categories

    @Test func terraformProjectStateIsOneSafeItem() async throws {
        let dir = try TempDir()
        try dir.file("Development/repos/app/.terraform/providers/x", bytes: 1_000_000)
        try dir.file("Documents/stack/.terraform/modules/m", bytes: 500_000)
        let result = try await RuleScanner(home: dir.url).scan(try rule("terraform-build-dirs"))
        #expect(result.items.count == 2)
        #expect(result.items.allSatisfy { $0.url.lastPathComponent == ".terraform" })
        #expect(result.items.allSatisfy { $0.risk == .safe && $0.mode == .permanent })
        #expect(result.totalBytes > 1_400_000)
    }

    @Test func terraformPluginCacheIsOneSafeItem() async throws {
        let dir = try TempDir()
        try dir.file(".terraform.d/plugin-cache/registry.opentofu.org/aws/provider", bytes: 3_000_000)
        let items = try await RuleScanner(home: dir.url).scan(try rule("terraform-plugin-cache")).items
        #expect(items.map(\.url.lastPathComponent) == ["plugin-cache"])
        #expect(items.allSatisfy { $0.risk == .safe && $0.mode == .permanent })
    }

    @Test func terragruntCacheIsReviewTrashAtDepthNine() async throws {
        let dir = try TempDir()
        try dir.file("Development/r1/r2/r3/r4/r5/r6/r7/f/.terragrunt-cache/hash/main.tf", bytes: 2_000_000)
        let items = try await RuleScanner(home: dir.url).scan(try rule("terragrunt-cache")).items
        #expect(items.map(\.url.lastPathComponent) == [".terragrunt-cache"])
        #expect(items.allSatisfy { $0.risk == .review && $0.mode == .trash })
    }

    @Test func terraformSkipsTerragruntCache() async throws {
        let dir = try TempDir()
        try dir.file("Development/app/.terraform/providers/y", bytes: 1_000_000)
        try dir.file("Development/app/.terragrunt-cache/hash/hash/.terraform/providers/x", bytes: 2_000_000)
        let result = try await RuleScanner(home: dir.url).scan(try rule("terraform-build-dirs"))
        #expect(result.items.map(\.url.lastPathComponent) == [".terraform"])
        #expect(result.totalBytes < 2_000_000)
    }

    @Test func virtualBoxMachinesComeFromRegistry() async throws {
        let dir = try TempDir()
        try dir.file("machines/lab-a/lab-a.vbox", bytes: 100)
        try dir.file("machines/lab-a/box.vdi", bytes: 2_000_000)
        try dir.file("machines/lab-b/lab-b.vbox", bytes: 100)
        let a = dir.url.appendingPathComponent("machines/lab-a/lab-a.vbox").path
        let b = dir.url.appendingPathComponent("machines/lab-b/lab-b.vbox").path
        try dir.text(
            "Library/VirtualBox/VirtualBox.xml",
            """
            <?xml version="1.0"?>
            <VirtualBox>
              <Global>
                <MachineRegistry>
                  <MachineEntry uuid="{1}" src="\(a)"/>
                  <MachineEntry uuid="{2}" src="\(b)"/>
                </MachineRegistry>
              </Global>
            </VirtualBox>
            """)
        let items = try await RuleScanner(home: dir.url).scan(try rule("virtualbox-machines")).items
        #expect(items.map(\.url.lastPathComponent) == ["lab-a", "lab-b"])
        #expect(items.allSatisfy { $0.risk == .review && $0.mode == .trash })
        #expect(items.allSatisfy { $0.ownerBundleID == "org.virtualbox.app.VirtualBox" })
    }

    @Test func virtualBoxFallsBackToDefaultMachineFolder() async throws {
        let dir = try TempDir()
        try dir.file("VMs/one/one.vbox", bytes: 100)
        try dir.file("VMs/two/two.vbox", bytes: 100)
        let machines = dir.url.appendingPathComponent("VMs").path
        try dir.text(
            "Library/VirtualBox/VirtualBox.xml",
            """
            <VirtualBox><Global><SystemProperties defaultMachineFolder="\(machines)"/></Global></VirtualBox>
            """)
        let items = try await RuleScanner(home: dir.url).scan(try rule("virtualbox-machines")).items
        #expect(items.map(\.url.lastPathComponent) == ["one", "two"])
    }

    @Test func virtualBoxWithoutRegistryUsesDefaultFolder() async throws {
        let dir = try TempDir()
        try dir.file("VirtualBox VMs/vm1/vm1.vbox", bytes: 100)
        let items = try await RuleScanner(home: dir.url).scan(try rule("virtualbox-machines")).items
        #expect(items.map(\.url.lastPathComponent) == ["vm1"])
    }

    @Test func virtualBoxDefaultFolderSkipsFoldersThatAreNotMachines() async throws {
        let dir = try TempDir()
        try dir.file("VirtualBox VMs/vm1/vm1.vbox", bytes: 100)
        try dir.file("VirtualBox VMs/notes/readme.txt", bytes: 100)
        let items = try await RuleScanner(home: dir.url).scan(try rule("virtualbox-machines")).items
        #expect(items.map(\.url.lastPathComponent) == ["vm1"])
    }

    @Test func devGarbageFindsStandaloneViteCache() async throws {
        let dir = try TempDir()
        try dir.file("Development/web/.vite/deps/lodash.js", bytes: 400_000)
        let items = try await RuleScanner(home: dir.url).scan(try rule("dev-garbage")).items
        #expect(items.map(\.url.lastPathComponent) == [".vite"])
    }

    @Test func devGarbageFindsNextAndTurboBuildDirs() async throws {
        let dir = try TempDir()
        try dir.file("Development/site/.next/cache/chunk.js", bytes: 800_000)
        try dir.file("Development/site/.turbo/task.log", bytes: 200_000)
        let items = try await RuleScanner(home: dir.url).scan(try rule("dev-garbage")).items
        #expect(Set(items.map(\.url.lastPathComponent)) == [".next", ".turbo"])
        #expect(items.allSatisfy { $0.risk == .review && $0.mode == .trash })
    }

    @Test func terraformDirHoldingStateIsReviewNotSafe() async throws {
        let dir = try TempDir()
        try dir.file("Development/app/.terraform/old/terraform.tfstate", bytes: 4_000)
        let items = try await RuleScanner(home: dir.url).scan(try rule("terraform-build-dirs")).items
        #expect(items.map(\.url.lastPathComponent) == [".terraform"])
        #expect(items.allSatisfy { $0.risk == .review && $0.mode == .trash })
    }

    @Test func terraformDirWithBackendConfigStaysSafe() async throws {
        let dir = try TempDir()
        try dir.file("Development/app/.terraform/terraform.tfstate", bytes: 200)
        try dir.file("Development/app/.terraform/providers/x/bin", bytes: 900_000)
        let items = try await RuleScanner(home: dir.url).scan(try rule("terraform-build-dirs")).items
        #expect(items.map(\.url.lastPathComponent) == [".terraform"])
        #expect(items.allSatisfy { $0.risk == .safe && $0.mode == .permanent })
    }

    @Test func virtualBoxRuntimeStateIsNotACleanupRule() {
        #expect(Rule.catalog.allSatisfy { $0.id != "virtualbox-support" })
        #expect(Rule.catalog.allSatisfy { !$0.roots.contains("Library/VirtualBox") })
        #expect(Rule.catalog.contains { $0.id == "virtualbox-machines" })
    }

    @Test func devGarbageSkipsMiseInstallTrees() async throws {
        let dir = try TempDir()
        try dir.file(
            "Development/sdks/mise/installs/npm-socket/1.14.1/node_modules/x/index.js", bytes: 1_000_000)
        try dir.file(
            "Development/sdks/mise/installs/node/26.13.0/lib/node_modules/npm/package.json", bytes: 1_000_000)
        try dir.file("Development/.mise/installs/npm-y/1.0.0/node_modules/y/index.js", bytes: 1_000_000)
        try dir.file("Development/repos/app/node_modules/express/index.js", bytes: 1_000_000)
        let items = try await RuleScanner(home: dir.url).scan(try rule("dev-garbage")).items
        #expect(
            items.map(\.url.path) == [
                dir.url.appendingPathComponent("Development/repos/app/node_modules").path
            ])
    }

    @Test func devGarbageFindsFlutterBuildDirs() async throws {
        let dir = try TempDir()
        try dir.file("Development/repos/app/build/app/outputs/flutter-apk/app-release.apk", bytes: 900_000)
        try dir.file("Development/repos/app/.dart_tool/package_config.json", bytes: 10_000)
        let items = try await RuleScanner(home: dir.url).scan(try rule("dev-garbage")).items
        #expect(Set(items.map(\.url.lastPathComponent)) == ["build", ".dart_tool"])
        #expect(items.allSatisfy { $0.risk == .review && $0.mode == .trash })
    }

    @Test func excludedFolderIsNotScanned() async throws {
        let dir = try TempDir()
        try dir.file("Library/Caches/a/x", bytes: 100)
        try dir.file("Library/Caches/keep/y", bytes: 100)
        try dir.file("Development/app/target/bin", bytes: 100)
        try dir.file("Development/keep/target/bin", bytes: 500_000)
        let keep = dir.url.appendingPathComponent("Library/Caches/keep").path
        let keepProject = dir.url.appendingPathComponent("Development/keep").path
        let scanner = RuleScanner(home: dir.url, excludedPaths: [keep, keepProject])
        #expect(try await scanner.scan(try rule("caches")).items.map(\.url.lastPathComponent) == ["a"])
        let buildDirs = try await scanner.scan(try rule("dev-garbage")).items.map(\.url.path)
        #expect(buildDirs.count == 1)
        #expect(buildDirs.first?.hasSuffix("Development/app/target") == true)
    }
}
