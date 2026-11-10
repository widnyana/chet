import Foundation
import Testing

@testable import ChetCore

struct GoModulesTests {
    private func existing(_ paths: String...) -> (String) -> Bool {
        { paths.contains($0) }
    }

    private func goScript(
        in dir: TempDir, cache: String, versionFails: Bool = false
    ) throws -> String {
        let target = dir.url.appendingPathComponent("bin/go")
        let version =
            versionFails
            ? "echo unavailable >&2; exit 1"
            : "echo \"go version go1.23.4 darwin/arm64\""
        let script = """
            #!/bin/sh
            case "$1" in
              version) \(version) ;;
              env) echo "GOMODCACHE=\(cache)"; echo "GOPATH=\(dir.url.path)/go" ;;
              *) exit 1 ;;
            esac
            """
        try dir.text("bin/go", script)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: target.path)
        return target.path
    }

    private func tool(
        _ requested: String, installPath: String?, name: String = "go", active: Bool = false,
        installed: Bool = true
    ) -> Mise.Tool {
        Mise.Tool(
            name: name, requested: requested, resolved: nil, installPath: installPath,
            active: active, installed: installed)
    }

    @Test func miseLocationPrefersActiveOverInstalled() {
        let tools = [
            tool("1.27.3", installPath: "/m/a"),
            tool("1.9.4", installPath: "/m/b", active: true),
        ]
        #expect(
            GoModules.miseLocation(from: tools)
                == GoModules.Location(executable: "/m/b/bin/go", source: .mise))
    }

    @Test func miseLocationPicksInstalledWhenNoneIsActive() {
        let tools = [
            tool("1.27.1", installPath: "/m/a", installed: false),
            tool("1.22.0", installPath: "/m/b"),
            tool("1.27.3", installPath: "/m/c"),
        ]
        #expect(GoModules.miseLocation(from: tools)?.executable == "/m/b/bin/go")
    }

    @Test func miseLocationSkipsNonGoRows() {
        let tools = [
            tool("1.27.1", installPath: "/m/golang", name: "golang", active: true),
            tool("1.27.3", installPath: "/m/go"),
        ]
        #expect(GoModules.miseLocation(from: tools)?.executable == "/m/go/bin/go")
    }

    @Test func miseLocationSkipsRowsWithoutInstallPath() {
        let tools = [
            tool("1.27.1", installPath: nil, active: true),
            tool("1.27.3", installPath: "/m/go"),
        ]
        #expect(GoModules.miseLocation(from: tools)?.executable == "/m/go/bin/go")
    }

    @Test func miseLocationIsNilForEmptyRows() {
        #expect(GoModules.miseLocation(from: []) == nil)
    }

    @Test func locatePrefersMiseOverPath() {
        let location = GoModules.locate(
            environment: ["PATH": "/tools/bin", "HOME": "/Users/test"],
            exists: existing("/tools/bin/go", "/mise/go/1.27.1/bin/go"),
            run: { _, _ in Subprocess.Result(status: 1, out: "", err: "") },
            miseTools: [tool("1.27.1", installPath: "/mise/go/1.27.1", active: true)])

        #expect(
            location
                == GoModules.Location(executable: "/mise/go/1.27.1/bin/go", source: .mise))
    }

    @Test func locateFallsThroughToPathWithNoMiseTools() {
        let location = GoModules.locate(
            environment: ["PATH": "/tools/bin", "HOME": "/Users/test"],
            exists: existing("/tools/bin/go"),
            run: { _, _ in Subprocess.Result(status: 1, out: "", err: "") },
            miseTools: [])

        #expect(location == GoModules.Location(executable: "/tools/bin/go", source: .path))
    }

    @Test func locateFallsThroughToHomebrewWithNoPathHit() {
        let location = GoModules.locate(
            environment: ["PATH": "/tools/bin", "HOME": "/Users/test"],
            exists: existing("/opt/homebrew/bin/go"),
            run: { _, _ in Subprocess.Result(status: 1, out: "", err: "") },
            miseTools: [])

        #expect(location?.executable == "/opt/homebrew/bin/go")
        #expect(location?.source == .homebrew)
    }

    @Test func highestMiseInstallWins() throws {
        let dir = try TempDir()
        try dir.file(".mise/installs/go/1.9.4/bin/go", bytes: 1)
        try dir.file(".mise/installs/go/1.27.3/bin/go", bytes: 1)
        let old = dir.url.appendingPathComponent(".mise/installs/go/1.9.4/bin/go").path
        let new = dir.url.appendingPathComponent(".mise/installs/go/1.27.3/bin/go").path

        let location = GoModules.locate(
            environment: ["PATH": "", "HOME": dir.url.path],
            exists: existing(old, new),
            run: { _, _ in Subprocess.Result(status: 1, out: "", err: "") },
            miseTools: [])

        #expect(location?.executable == new)
        #expect(location?.source == .mise)
    }

    @Test func concreteGVmInstallBeatsShim() throws {
        let dir = try TempDir()
        try dir.file(".gvm/gos/go1.22.5/bin/go", bytes: 1)
        try dir.file(".local/share/mise/shims/go", bytes: 1)
        let install = dir.url.appendingPathComponent(".gvm/gos/go1.22.5/bin/go").path
        let shim = dir.url.appendingPathComponent(".local/share/mise/shims/go").path

        let location = GoModules.locate(
            environment: ["PATH": "", "HOME": dir.url.path],
            exists: existing(install, shim),
            run: { _, _ in Subprocess.Result(status: 1, out: "", err: "") },
            miseTools: [])

        #expect(location?.executable == install)
        #expect(location?.source == .gvm)
    }

    @Test func locateUsesShimWhenNothingElseExists() throws {
        let dir = try TempDir()
        try dir.file(".local/share/mise/shims/go", bytes: 1)
        let shim = dir.url.appendingPathComponent(".local/share/mise/shims/go").path

        let location = GoModules.locate(
            environment: ["PATH": "", "HOME": dir.url.path],
            exists: existing(shim),
            run: { _, _ in Subprocess.Result(status: 1, out: "", err: "") },
            miseTools: [])

        #expect(location?.executable == shim)
        #expect(location?.source == .shim)
    }

    @Test func parseEnvHandlesCRLFAndBlanks() {
        let parsed = GoModules.parseEnv(
            "GOMODCACHE=/a/mod\r\n\r\n  \r\nGOPATH=/a/go\r\nNOISE\r\nEMPTY=\r\n")
        #expect(parsed["GOMODCACHE"] == "/a/mod")
        #expect(parsed["GOPATH"] == "/a/go")
        #expect(parsed["EMPTY"] == "")
        #expect(parsed["NOISE"] == nil)
    }

    @Test func cachePathPrefersReportedThenEnvironmentValues() {
        let reported = GoModules.cachePath(
            for: "/go/bin/go",
            environment: ["GOMODCACHE": "/env/mod", "GOPATH": "/env/go", "HOME": "/home"],
            run: { _, _ in
                Subprocess.Result(status: 0, out: "GOMODCACHE=/go/pkg/mod\r\nGOPATH=/go\r\n", err: "")
            })
        #expect(reported == "/go/pkg/mod")

        let envCache = GoModules.cachePath(
            for: "/go/bin/go",
            environment: ["GOMODCACHE": "/env/mod", "GOPATH": "/env/go", "HOME": "/home"],
            run: { _, _ in Subprocess.Result(status: 0, out: "GOMODCACHE=\nGOPATH=", err: "") })
        #expect(envCache == "/env/mod")

        let reportedGopath = GoModules.cachePath(
            for: "/go/bin/go",
            environment: ["HOME": "/home"],
            run: { _, _ in Subprocess.Result(status: 0, out: "GOMODCACHE=\nGOPATH=/go", err: "") })
        #expect(reportedGopath == "/go/pkg/mod")

        let envGopath = GoModules.cachePath(
            for: "/go/bin/go",
            environment: ["GOPATH": "/env/go", "HOME": "/home"],
            run: { _, _ in Subprocess.Result(status: 0, out: "", err: "") })
        #expect(envGopath == "/env/go/pkg/mod")

        let home = GoModules.cachePath(
            for: "/go/bin/go",
            environment: ["HOME": "/home"],
            run: { _, _ in Subprocess.Result(status: 0, out: "", err: "") })
        #expect(home == "/home/go/pkg/mod")

        let bare = GoModules.cachePath(
            for: "/go/bin/go",
            environment: ["HOME": "/home"],
            run: { _, _ in Subprocess.Result(status: 0, out: "/bare/mod\n", err: "") })
        #expect(bare == "/bare/mod")
    }

    @Test func measureSumsDownloadSubtreeAndCountsModules() throws {
        let dir = try TempDir()
        let cache = dir.url.appendingPathComponent("go/pkg/mod")
        try dir.file("go/pkg/mod/cache/download/golang.org/x/text/@v/v0.3.0.zip", bytes: 65_536)
        try dir.file("go/pkg/mod/cache/download/sumdb/lookup.txt", bytes: 4_096)
        try dir.file("go/pkg/mod/github.com/foo/bar@v1.2.3/bar.go", bytes: 8_192)
        try dir.file("go/pkg/mod/github.com/foo/baz@v0.1.0/baz.go", bytes: 16_384)
        let executable = try goScript(in: dir, cache: cache.path)

        let info = GoModules.measure(GoModules.Location(executable: executable, source: .path))

        #expect(info.version == "go version go1.23.4 darwin/arm64")
        #expect(info.cachePath == cache.path)
        #expect(info.executable == executable && info.source == .path)
        #expect(info.moduleCount == 2)
        let expected =
            FS.usage(cache.appendingPathComponent("cache/download").path).size
            + FS.usage(cache.appendingPathComponent("github.com/foo").path).size
        #expect(info.bytes == expected)
        #expect(info.bytes >= 65_536 + 4_096 + 8_192 + 16_384)
    }

    @Test func symlinkAddsNoBytes() throws {
        let dir = try TempDir()
        let cache = dir.url.appendingPathComponent("go/pkg/mod")
        try dir.file("go/pkg/mod/cache/download/golang.org/x/text/@v/v0.3.0.zip", bytes: 65_536)
        try dir.file("go/pkg/mod/github.com/foo/bar@v1.2.3/bar.go", bytes: 8_192)
        let executable = try goScript(in: dir, cache: cache.path)
        let location = GoModules.Location(executable: executable, source: .path)

        let before = GoModules.measure(location)
        try FileManager.default.createSymbolicLink(
            at: cache.appendingPathComponent("download-link"),
            withDestinationURL: cache.appendingPathComponent("cache"))
        let after = GoModules.measure(location)

        #expect(after.bytes == before.bytes)
        #expect(after.moduleCount == before.moduleCount)
        #expect(after.moduleCount == 1)
    }

    @Test func measureMissingRootReadsZero() throws {
        let dir = try TempDir()
        let missing = dir.url.appendingPathComponent("absent/mod")
        let executable = try goScript(in: dir, cache: missing.path, versionFails: true)

        let info = GoModules.measure(GoModules.Location(executable: executable, source: .path))

        #expect(info.version == "Go")
        #expect(info.bytes == 0)
        #expect(info.moduleCount == 0)
    }

    @Test func dryRunCleanSpawnsNothing() throws {
        let dir = try TempDir()
        let executable = dir.url.appendingPathComponent("bin/go")
        let marker = dir.url.appendingPathComponent("invoked").path
        try dir.text("bin/go", "#!/bin/sh\necho \"$@\" > \"\(marker)\"\n")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let location = GoModules.Location(executable: executable.path, source: .path)

        let dry = GoModules.clean(location, dryRun: true)
        #expect(dry.status == 0)
        #expect(dry.out == "Would run: \(executable.path) clean -modcache")
        #expect(dry.err.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: marker))

        let real = GoModules.clean(location, dryRun: false)
        #expect(real.ok)
        let invoked = String(
            decoding: try Data(contentsOf: URL(fileURLWithPath: marker)), as: UTF8.self)
        #expect(invoked.trimmingCharacters(in: .whitespacesAndNewlines) == "clean -modcache")
    }

    @Test func cleanReportsMissingExecutable() throws {
        let dir = try TempDir()
        let missing = dir.url.appendingPathComponent("no-go").path

        let result = GoModules.clean(
            GoModules.Location(executable: missing, source: .path), dryRun: false)

        #expect(result.status != 0)
        #expect(!result.message.isEmpty)
    }
}
