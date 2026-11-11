import Foundation
import Testing

@testable import ChetCore

struct HomebrewParseTests {
    private let fixture = """
        {
          "formulae": [
            {"name":"libpng","desc":"PNG library","homepage":"https://libpng.example",
             "outdated":false,"pinned":false,"versions":{"stable":"1.6.40"},"linked_keg":"1.6.40",
             "installed":[{"version":"1.6.40","installed_on_request":true,
               "runtime_dependencies":[{"full_name":"zlib","declared_directly":true}]}]},
            {"name":"zlib","desc":"Compression","homepage":"https://zlib.example",
             "outdated":true,"pinned":false,"versions":{"stable":"1.3"},"linked_keg":"1.2.13",
             "installed":[{"version":"1.2.13","installed_on_request":false,"runtime_dependencies":[]}]},
            {"name":"orphan","desc":"Unused","homepage":"https://orphan.example",
             "outdated":false,"pinned":true,"versions":{"stable":"2.0"},"linked_keg":"2.0",
             "installed":[{"version":"2.0","installed_on_request":false,"runtime_dependencies":[]}]}
          ],
          "casks": [
            {"token":"figma","name":["Figma"],"desc":"Design tool","homepage":"https://figma.example",
             "installed":"118.0","version":"120.0","outdated":true,"depends_on":{},
             "artifacts":[{"app":["Figma.app"]}]}
          ]
        }
        """

    @Test func parsesFormulaeAndCasksWithReverseDeps() throws {
        let packages = try Homebrew.parse(fixture)
        let libpng = try #require(packages.first { $0.name == "libpng" })
        let zlib = try #require(packages.first { $0.name == "zlib" })
        let orphan = try #require(packages.first { $0.name == "orphan" })
        let figma = try #require(packages.first { $0.name == "figma" })

        #expect(libpng.deps == ["zlib"])
        #expect(libpng.onRequest)
        #expect(!libpng.isUnusedDependency)

        #expect(zlib.usedBy == ["libpng"])
        #expect(zlib.outdated)
        #expect(zlib.version == "1.2.13" && zlib.latest == "1.3")
        #expect(!zlib.isUnusedDependency)

        #expect(orphan.isUnusedDependency)
        #expect(orphan.pinned)

        #expect(figma.kind == .cask)
        #expect(figma.title == "Figma")
        #expect(figma.version == "118.0" && figma.latest == "120.0")
    }

    @Test func invalidOutputThrows() {
        #expect(throws: BrewError.self) { try Homebrew.parse("not json") }
    }

    @Test func sizedCountsEveryKegVersionAndTheCaskRoom() throws {
        let dir = try TempDir()
        try dir.file("Cellar/demo/1.0/bin/demo", bytes: 1_000_000)
        try dir.file("Cellar/demo/2.0/bin/demo", bytes: 2_000_000)
        try dir.file("Caskroom/thing/3.0/Thing.app/data", bytes: 3_000_000)
        let formula = BrewPackage(
            kind: .formula, name: "demo", title: "demo", desc: "", homepage: "",
            version: "2.0", latest: "2.0", outdated: false, pinned: false, onRequest: true, deps: [])
        let cask = BrewPackage(
            kind: .cask, name: "thing", title: "Thing", desc: "", homepage: "",
            version: "3.0", latest: "3.0", outdated: false, pinned: false, onRequest: true, deps: [])

        let sized = Homebrew.sized([formula, cask], root: dir.url.path)
        let old = FS.usage(dir.url.appendingPathComponent("Cellar/demo/1.0").path).size
        let new = FS.usage(dir.url.appendingPathComponent("Cellar/demo/2.0").path).size
        let caskRoom = FS.usage(dir.url.appendingPathComponent("Caskroom/thing").path).size

        #expect(sized[0].size == old + new)
        #expect(sized[0].oldVersionsSize == old)
        #expect(sized[0].paths == [dir.url.appendingPathComponent("Cellar/demo").path])
        #expect(sized[1].size == caskRoom)
        #expect(sized[1].paths == [dir.url.appendingPathComponent("Caskroom/thing").path])
    }

    @Test func dryRunUpgradeNamesOnlyTheFormula() {
        let formula = BrewPackage(
            kind: .formula, name: "libpng", title: "libpng", desc: "", homepage: "",
            version: "1.6.40", latest: "1.6.41", outdated: true, pinned: false,
            onRequest: true, deps: [])

        let result = Homebrew.upgrade([formula], dryRun: true)

        #expect(result.ok)
        #expect(result.out == "Would run: brew upgrade --formula libpng")
        #expect(!result.out.contains("--cask"))
    }

    @Test func dryRunUpgradeNamesOnlyTheCask() {
        let cask = BrewPackage(
            kind: .cask, name: "figma", title: "Figma", desc: "", homepage: "",
            version: "118.0", latest: "120.0", outdated: true, pinned: false,
            onRequest: true, deps: [])

        let result = Homebrew.upgrade([cask], dryRun: true)

        #expect(result.ok)
        #expect(result.out == "Would run: brew upgrade --cask figma")
        #expect(!result.out.contains("--formula"))
    }

    @Test func dryRunUninstallAndCleanupNeverRunBrew() {
        // Safe without brew installed: the dry-run paths never spawn a process.
        let pkg = BrewPackage(
            kind: .formula, name: "libpng", title: "libpng", desc: "", homepage: "",
            version: "1.6.40", latest: "1.6.40", outdated: false, pinned: false,
            onRequest: true, deps: [])

        let uninstall = Homebrew.uninstall([pkg], zap: false, dryRun: true)
        #expect(uninstall.ok)
        #expect(uninstall.out.hasPrefix("Would run: brew uninstall"))

        let cleanup = Homebrew.cleanup(dryRun: true)
        #expect(cleanup.result.ok)
        #expect(cleanup.freed == nil)
    }
}
