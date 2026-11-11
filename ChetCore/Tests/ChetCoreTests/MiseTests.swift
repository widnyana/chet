import Foundation
import Testing

@testable import ChetCore

struct MiseTests {
    @Test func parseConfigReadsOnlyTheToolsTable() {
        let text = """
            [settings]
            experimental = true

            [plugins]
            foo = "bar"

            [tools]
            node = "20.11.0"
            "python@3.12" = "3.12.1"
            'aqua:awscli' = '2.15.0'
            terraform = { version = "1.7.5" }
            "npm:biome" = ["1.9.4", "2.0.0"]
            # java = "21"
            """

        let declared = Mise.parseConfig(text)

        #expect(
            Set(declared) == [
                Mise.Declared(name: "node", version: "20.11.0"),
                Mise.Declared(name: "python@3.12", version: "3.12.1"),
                Mise.Declared(name: "aqua:awscli", version: "2.15.0"),
                Mise.Declared(name: "terraform", version: "1.7.5"),
                Mise.Declared(name: "npm:biome", version: "1.9.4"),
                Mise.Declared(name: "npm:biome", version: "2.0.0"),
            ])
        #expect(declared.count == 6)
    }

    @Test func detectWithToolsButNoBinaryIsUnavailable() throws {
        let home = try TempDir()
        try home.text(".config/mise/config.toml", "[tools]\nnode = \"20.11.0\"\n")

        let detection = Mise.detect(home: home.url, path: "")

        #expect(detection.configExists)
        #expect(detection.declared == [Mise.Declared(name: "node", version: "20.11.0")])
        #expect(detection.executable == nil)
        #expect(!detection.available)
    }

    @Test func detectWithoutToolsNeverResolvesTheBinary() throws {
        let home = try TempDir()
        try makeExecutable(home.url.appendingPathComponent(".local/bin/mise"))

        let missing = Mise.detect(home: home.url, path: "")
        #expect(!missing.configExists)
        #expect(missing.declared.isEmpty)
        #expect(missing.executable == nil)
        #expect(!missing.available)

        try home.text(".config/mise/config.toml", "[settings]\nexperimental = true\n")

        let empty = Mise.detect(home: home.url, path: "")
        #expect(empty.configExists)
        #expect(empty.declared.isEmpty)
        #expect(empty.executable == nil)
        #expect(!empty.available)
    }

    @Test func detectPrefersTheHomeBinaryOverPath() throws {
        let home = try TempDir()
        try home.text(".config/mise/config.toml", "[tools]\nnode = \"20.11.0\"\n")
        let local = home.url.appendingPathComponent(".local/bin/mise")
        try makeExecutable(local)
        let pathBinary = try home.text("pathbin/mise", "#!/bin/sh\n")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: pathBinary.path)

        let detection = Mise.detect(
            home: home.url, path: home.url.appendingPathComponent("pathbin").path)

        #expect(detection.available)
        #expect(detection.executable == local.path)
        #expect(detection.executable != pathBinary.path)
    }

    @Test func detectFallsBackToPathAndIgnoresANonExecutableHomeBinary() throws {
        let home = try TempDir()
        try home.text(".config/mise/config.toml", "[tools]\nnode = \"20.11.0\"\n")
        let local = try home.text(".local/bin/mise", "#!/bin/sh\n")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644], ofItemAtPath: local.path)
        let pathBinary = try home.text("tools/mise", "#!/bin/sh\n")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: pathBinary.path)

        let detection = Mise.detect(
            home: home.url, path: home.url.appendingPathComponent("tools").path)

        #expect(detection.available)
        #expect(detection.executable == pathBinary.path)
        #expect(detection.executable != local.path)
    }

    @Test func parseResolvedKeepsBackendKeysAndUninstalledEntriesNeverMatch() throws {
        let json = """
            {
              "aqua:awscli": [
                {"version":"2.15.0","installed":true,"active":true,
                 "install_path":"/tools/aws","source":"aqua","requested_version":"latest"}
              ],
              "npm:biome": [
                {"version":"1.9.4","installed":false,"active":false,"install_path":"/tools/biome"}
              ]
            }
            """

        let parsed = try #require(Mise.parseResolved(json))
        #expect(Set(parsed.keys) == ["aqua:awscli", "npm:biome"])

        let aws = try #require(parsed["aqua:awscli"]?.first)
        #expect(aws.version == "2.15.0")
        #expect(aws.installPath == "/tools/aws")
        #expect(aws.installed && aws.active)
        #expect(parsed["npm:biome"]?.first?.installed == false)

        let tools = Mise.rows(
            declared: [Mise.Declared(name: "npm:biome", version: "1.9.4")], resolved: parsed)

        #expect(tools.count == 2)
        let biome = try #require(tools.first { $0.name == "npm:biome" })
        #expect(biome.version == "1.9.4")
        #expect(biome.resolved == nil)
        #expect(!biome.installed)
        #expect(biome.declared)

        let awsRow = try #require(tools.first { $0.name == "aqua:awscli" })
        #expect(awsRow.requested.isEmpty)
        #expect(!awsRow.declared)
        #expect(awsRow.installed)
    }

    @Test func rowsKeepEveryInstalledVersionAndMarkTheDeclaredOne() throws {
        let resolved: [String: [Mise.Resolved]] = [
            "terragrunt": [
                Mise.Resolved(
                    version: "1.1.3", installPath: "/t/1.1.3", installed: true, active: false),
                Mise.Resolved(
                    version: "1.1.5", installPath: "/t/1.1.5", installed: true, active: false),
                Mise.Resolved(
                    version: "1.2.1", installPath: "/t/1.2.1", installed: true, active: true),
            ],
            "uv": [
                Mise.Resolved(
                    version: "0.12.15", installPath: "/u/0.12.15", installed: true, active: false),
                Mise.Resolved(
                    version: "0.12.17", installPath: "/u/0.12.17", installed: true, active: false),
                Mise.Resolved(
                    version: "0.13.6", installPath: "/u/0.13.6", installed: true, active: false),
                Mise.Resolved(
                    version: "0.13.7", installPath: "/u/0.13.7", installed: true, active: true),
            ],
        ]
        let declared = [
            Mise.Declared(name: "terragrunt", version: "latest"),
            Mise.Declared(name: "uv", version: "0.13.7"),
        ]

        let tools = Mise.rows(declared: declared, resolved: resolved)

        let terragrunt = tools.filter { $0.name == "terragrunt" }
        #expect(terragrunt.count == 3)
        #expect(terragrunt.map(\.version) == ["1.2.1", "1.1.5", "1.1.3"])
        #expect(terragrunt.filter(\.declared).map(\.version) == ["1.2.1"])
        #expect(terragrunt.allSatisfy { $0.installed })
        #expect(terragrunt.allSatisfy { $0.requested == "latest" })
        #expect(terragrunt.filter(\.active).map(\.version) == ["1.2.1"])

        let uv = tools.filter { $0.name == "uv" }
        #expect(uv.count == 4)
        #expect(uv.map(\.version) == ["0.13.7", "0.13.6", "0.12.17", "0.12.15"])
        #expect(uv.filter(\.declared).map(\.version) == ["0.13.7"])
        #expect(uv.allSatisfy { $0.installed })
        #expect(uv.allSatisfy { $0.requested == "0.13.7" })
        #expect(Set(tools.map(\.id)).count == tools.count)
    }

    @Test func rowsMarkOnlyTheActiveInstalledVersionForLatest() throws {
        let resolved: [String: [Mise.Resolved]] = [
            "node": [
                Mise.Resolved(
                    version: "20.10.0", installPath: "/n/20.10.0", installed: true, active: true),
                Mise.Resolved(
                    version: "20.11.0", installPath: "/n/20.11.0", installed: true, active: false),
            ]
        ]

        let tools = Mise.rows(
            declared: [Mise.Declared(name: "node", version: "latest")], resolved: resolved)

        #expect(tools.count == 2)
        #expect(tools.filter(\.declared).map(\.version) == ["20.10.0"])
        #expect(tools.first { $0.version == "20.11.0" }?.declared == false)
        #expect(tools.first { $0.version == "20.10.0" }?.active == true)
    }

    @Test func rowsKeepADeclaredVersionWithoutAnInstall() throws {
        let resolved: [String: [Mise.Resolved]] = [
            "node": [
                Mise.Resolved(
                    version: "20.11.0", installPath: "/n/20.11.0", installed: true, active: true)
            ]
        ]

        let tools = Mise.rows(
            declared: [Mise.Declared(name: "node", version: "18.20.0")], resolved: resolved)

        #expect(tools.count == 2)
        #expect(tools[0].version == "18.20.0")
        #expect(tools[0].declared)
        #expect(!tools[0].installed)
        #expect(tools[0].resolved == nil)
        #expect(tools[0].installPath == nil)
        #expect(tools[0].requested == "18.20.0")
        #expect(tools[1].version == "20.11.0")
        #expect(!tools[1].declared)
        #expect(tools[1].installed)
    }

    @Test func rowsOrderVersionsNumericallyDescending() {
        let resolved: [String: [Mise.Resolved]] = [
            "node": [
                Mise.Resolved(
                    version: "1.27.9", installPath: "/n/1.27.9", installed: true, active: false),
                Mise.Resolved(
                    version: "1.27.10", installPath: "/n/1.27.10", installed: true, active: false),
                Mise.Resolved(
                    version: "1.27.2", installPath: "/n/1.27.2", installed: true, active: false),
            ]
        ]

        let tools = Mise.rows(declared: [], resolved: resolved)

        #expect(tools.map(\.version) == ["1.27.10", "1.27.9", "1.27.2"])
        #expect(tools.allSatisfy { $0.requested.isEmpty })
        #expect(tools.allSatisfy { !$0.declared })
    }

    @Test func dataDirectoryPrefersTheEnvironment() throws {
        let home = try TempDir()
        let environmentDir = try installedDirectory(home.url, "env-mise")
        let configDir = try installedDirectory(home.url, "config-mise")
        try home.text(
            ".config/mise/config.toml", "[settings]\ndata_dir = \"\(configDir.path)\"\n")

        let resolved = Mise.dataDirectory(
            home: home.url, path: "", environment: ["MISE_DATA_DIR": environmentDir.path])

        #expect(resolved?.path == environmentDir.path)
    }

    @Test func dataDirectoryPrefersConfigSettingsOverSettingsFile() throws {
        let home = try TempDir()
        let configDir = try installedDirectory(home.url, "config-mise")
        let settingsDir = try installedDirectory(home.url, "settings-mise")
        try home.text(
            ".config/mise/config.toml", "[settings]\ndata_dir = \"\(configDir.path)\"\n")
        try home.text(
            ".config/mise/settings.toml", "data_dir = \"\(settingsDir.path)\"\n")

        let resolved = Mise.dataDirectory(home: home.url, path: "", environment: [:])

        #expect(resolved?.path == configDir.path)
    }

    @Test func dataDirectoryPrefersSettingsFileOverShellExport() throws {
        let home = try TempDir()
        let settingsDir = try installedDirectory(home.url, "settings-mise")
        let shellDir = try installedDirectory(home.url, "shell-mise")
        try home.text(
            ".config/mise/settings.toml", "data_dir = \"\(settingsDir.path)\"\n")
        try home.text(".zshrc", "export MISE_DATA_DIR=\"\(shellDir.path)\"\n")

        let resolved = Mise.dataDirectory(home: home.url, path: "", environment: [:])

        #expect(resolved?.path == settingsDir.path)
    }

    @Test func dataDirectoryIgnoresACommentedExport() throws {
        let home = try TempDir()
        let shellDir = try installedDirectory(home.url, "shell-mise")
        try home.text(".zshrc", "# export MISE_DATA_DIR=\"\(shellDir.path)\"\n")

        let resolved = Mise.dataDirectory(home: home.url, path: "", environment: [:])

        #expect(resolved == nil)
    }

    @Test func dataDirectoryExpandsHomeInShellExports() throws {
        let home = try TempDir()
        let first = try installedDirectory(home.url, "one")
        let second = try installedDirectory(home.url, "two")
        try home.text(".zshrc", "export MISE_DATA_DIR=\"$HOME/one\"\n")

        let expanded = Mise.dataDirectory(home: home.url, path: "", environment: [:])

        #expect(expanded?.path == first.path)

        try home.text(".zshrc", "export MISE_DATA_DIR=\"${HOME}/two\"\n")

        let braced = Mise.dataDirectory(home: home.url, path: "", environment: [:])

        #expect(braced?.path == second.path)
    }

    @Test func dataDirectoryScanFindsDevelopmentSDKsOnlyWithInstalls() throws {
        let home = try TempDir()
        let development = home.url.appendingPathComponent("Development/sdks/mise")
        try FileManager.default.createDirectory(at: development, withIntermediateDirectories: true)

        #expect(Mise.dataDirectory(home: home.url, path: "", environment: [:]) == nil)

        try FileManager.default.createDirectory(
            at: development.appendingPathComponent("installs"), withIntermediateDirectories: true)

        let resolved = Mise.dataDirectory(home: home.url, path: "", environment: [:])

        #expect(resolved?.path == development.path)
    }

    @Test func dataDirectoryFallsBackToTheDefault() throws {
        let home = try TempDir()
        let fallback = try installedDirectory(home.url, ".local/share/mise")

        let resolved = Mise.dataDirectory(home: home.url, path: "", environment: [:])

        #expect(resolved?.path == fallback.path)
    }

    @Test func dataDirectoryReturnsNilWhenNothingIsInstalledAndSnapshotKeepsDeclaredRows() throws {
        let home = try TempDir()
        try home.text(".config/mise/config.toml", "[tools]\nnode = \"20.11.0\"\n")

        #expect(Mise.dataDirectory(home: home.url, path: "", environment: [:]) == nil)

        let detection = Mise.detect(home: home.url, path: "")
        let snapshot = Mise.snapshot(detection)

        #expect(snapshot.tools.count == 1)
        #expect(snapshot.tools.first?.name == "node")
        #expect(snapshot.tools.first?.requested == "20.11.0")
        #expect(snapshot.tools.first?.installed == false)
    }

    @Test func parseResolvedRejectsNonObjectAndMalformedJSON() {
        #expect(Mise.parseResolved("") == nil)
        #expect(Mise.parseResolved("not json") == nil)
        #expect(Mise.parseResolved("[]") == nil)
        #expect(Mise.parseResolved(#"[{"version":"1.0.0"}]"#) == nil)
        #expect(Mise.parseResolved(#"{"node":"20.11.0"}"#) == nil)
    }
}

private func installedDirectory(_ home: URL, _ relative: String) throws -> URL {
    let directory = home.appendingPathComponent(relative)
    try FileManager.default.createDirectory(
        at: directory.appendingPathComponent("installs"), withIntermediateDirectories: true)
    return directory
}

private func makeExecutable(_ url: URL) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("#!/bin/sh\n".utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
}
