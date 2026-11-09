import Foundation

/// A formula or cask installed through Homebrew.
public struct BrewPackage: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable { case formula, cask }

    public let kind: Kind
    public let name: String
    public let title: String
    public let desc: String
    public let homepage: String
    public let version: String
    public let latest: String
    public let outdated: Bool
    public let pinned: Bool
    public let onRequest: Bool
    public let deps: [String]
    public var usedBy: [String] = []
    public var size: Int64 = 0
    public var oldVersionsSize: Int64 = 0
    public var paths: [String] = []

    public var id: String { "\(kind.rawValue):\(name)" }
    public var kindLabel: String { kind == .cask ? "Cask" : "Formula" }
    public var appPath: String? { paths.first { $0.hasSuffix(".app") } }
    public var isUnusedDependency: Bool { kind == .formula && !onRequest && usedBy.isEmpty }
}

public struct BrewError: Error, Sendable { public let message: String }

public enum Homebrew {
    public static let executable: String? = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    /// /opt/homebrew on Apple Silicon, /usr/local on Intel.
    public static var prefix: String? {
        executable.map {
            (($0 as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
        }
    }

    /// Apps launched from Finder get a bare PATH; brew and its tools need their own bin, and the
    /// noise-suppressing flags keep the JSON clean.
    private static var env: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        env["HOMEBREW_NO_COLOR"] = "1"
        env["HOMEBREW_NO_EMOJI"] = "1"
        if let prefix {
            env["PATH"] = "\(prefix)/bin:\(prefix)/sbin:" + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        }
        return env
    }

    private static func run(_ args: [String], timeout: TimeInterval = 60) -> Subprocess.Result {
        guard let executable else {
            return Subprocess.Result(status: -1, out: "", err: "Homebrew not found")
        }
        return Subprocess.run(executable, args, env: env, timeout: timeout)
    }

    /// One result from several brew invocations: the first failure's status, every stdout
    /// line, every failure message.
    private static func combine(_ outs: [Subprocess.Result]) -> Subprocess.Result {
        let failed = outs.filter { !$0.ok }
        return Subprocess.Result(
            status: failed.first?.status ?? 0,
            out: outs.map(\.out).joined(separator: "\n"),
            err: failed.map(\.message).joined(separator: "\n\n"))
    }

    /// The report a dry run returns in place of spawning a process.
    private static func wouldRun(_ command: String) -> Subprocess.Result {
        Subprocess.Result(status: 0, out: "Would run: " + command, err: "")
    }

    /// The dry-run report for a formula/cask split command: one line per non-empty group.
    private static func wouldRun(
        formulae: [String], casks: [String], verb: String, zap: Bool = false
    ) -> Subprocess.Result {
        var lines: [String] = []
        if !formulae.isEmpty {
            lines.append("Would run: brew \(verb) --formula " + formulae.joined(separator: " "))
        }
        if !casks.isEmpty {
            lines.append(
                "Would run: brew \(verb) --cask" + (zap ? " --zap" : "") + " "
                    + casks.joined(separator: " "))
        }
        return Subprocess.Result(status: 0, out: lines.joined(separator: "\n"), err: "")
    }

    /// Everything Homebrew has installed, with sizes measured on disk. Throws when `brew` fails
    /// or its output cannot be read.
    public static func installed() throws -> [BrewPackage] {
        let result = run(["info", "--json=v2", "--installed"])
        guard result.ok else { throw BrewError(message: result.message) }
        return sized(try parse(result.out))
    }

    /// Pure parse of `brew info --json=v2` output plus the reverse-dependency pass. No IO, so it
    /// is unit tested from a fixture.
    public static func parse(_ output: String) throws -> [BrewPackage] {
        guard let json = try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any]
        else {
            throw BrewError(message: "Couldn't read Homebrew's output.")
        }
        let formulae = (json["formulae"] as? [[String: Any]] ?? []).compactMap(formula)
        let casks = (json["casks"] as? [[String: Any]] ?? []).compactMap(cask)
        var all = formulae + casks

        var users: [String: [String]] = [:]
        for package in all {
            for dep in package.deps { users[dep, default: []].append(package.name) }
        }
        for index in all.indices where all[index].kind == .formula {
            all[index].usedBy = (users[all[index].name] ?? []).sorted()
        }
        return all
    }

    /// Measures each package's on-disk size in parallel. Writes go to distinct indices of a
    /// buffer pointer, which is safe, unlike mutating a Swift Array from several threads.
    private static func sized(_ packages: [BrewPackage]) -> [BrewPackage] {
        guard !packages.isEmpty, let prefix else { return packages }
        let cellar = prefix + "/Cellar"
        let caskroom = prefix + "/Caskroom"
        var out = packages
        out.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            // Each worker writes disjoint indices, so the shared base pointer is safe.
            nonisolated(unsafe) let base = baseAddress
            let count = buffer.count
            let workers = min(4, count)
            DispatchQueue.concurrentPerform(iterations: workers) { worker in
                var index = worker
                while index < count {
                    // One pool per package: the walk builds Foundation strings and arrays that
                    // would otherwise live until the worker finishes.
                    autoreleasepool {
                        var package = base[index]
                        if package.kind == .formula {
                            let keg = cellar + "/" + package.name
                            var total: Int64 = 0
                            var old: Int64 = 0
                            for version in FS.list(keg) ?? [] {
                                let size = FS.usage(keg + "/" + version).size
                                total += size
                                if version != package.version { old += size }
                            }
                            package.size = total
                            package.oldVersionsSize = old
                            package.paths = [keg]
                        } else {
                            let room = caskroom + "/" + package.name
                            package.size = FS.usage(room).size + package.paths.reduce(0) { $0 + FS.usage($1).size }
                            package.paths = package.paths + [room]
                        }
                        base[index] = package
                    }
                    index += workers
                }
            }
        }
        return out
    }

    private static func formula(_ f: [String: Any]) -> BrewPackage? {
        guard let name = f["name"] as? String else { return nil }
        let installed = f["installed"] as? [[String: Any]] ?? []
        let linked = f["linked_keg"] as? String
        let current = installed.first { ($0["version"] as? String) == linked } ?? installed.last
        let deps = (current?["runtime_dependencies"] as? [[String: Any]] ?? [])
            .filter { ($0["declared_directly"] as? Bool) ?? true }
            .compactMap { ($0["full_name"] as? String).map { ($0 as NSString).lastPathComponent } }
        let versions = f["versions"] as? [String: Any]
        return BrewPackage(
            kind: .formula, name: name, title: name,
            desc: f["desc"] as? String ?? "",
            homepage: f["homepage"] as? String ?? "",
            version: linked ?? current?["version"] as? String ?? "",
            latest: versions?["stable"] as? String ?? "",
            outdated: f["outdated"] as? Bool ?? false,
            pinned: f["pinned"] as? Bool ?? false,
            onRequest: installed.contains { ($0["installed_on_request"] as? Bool) == true },
            deps: deps)
    }

    private static func cask(_ c: [String: Any]) -> BrewPackage? {
        guard let token = c["token"] as? String else { return nil }
        let deps = ((c["depends_on"] as? [String: Any])?["formula"] as? [String] ?? [])
            .map { ($0 as NSString).lastPathComponent }
        let installedVersion = (c["installed"] as? String) ?? ""
        return BrewPackage(
            kind: .cask, name: token,
            title: (c["name"] as? [String])?.first ?? token,
            desc: c["desc"] as? String ?? "",
            homepage: c["homepage"] as? String ?? "",
            version: installedVersion,
            latest: c["version"] as? String ?? "",
            outdated: c["outdated"] as? Bool ?? false,
            pinned: false, onRequest: true, deps: deps,
            paths: appBundles(c["artifacts"] as? [Any] ?? []))
    }

    /// App bundles a cask installed, from its `app` artifacts. Only those that exist on disk.
    private static func appBundles(_ artifacts: [Any]) -> [String] {
        var out: [String] = []
        for case let artifact as [String: Any] in artifacts {
            guard let app = artifact["app"] as? [Any] else { continue }
            var name = app.first as? String
            for case let options as [String: Any] in app {
                if let target = options["target"] as? String { name = target }
            }
            guard let name else { continue }
            let target = (name as NSString).lastPathComponent
            let candidates =
                name.hasPrefix("/")
                ? [name]
                : ["/Applications/" + name, NSHomeDirectory() + "/Applications/" + target]
            if let hit = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) {
                out.append(hit)
            }
        }
        return out
    }

    /// `brew uninstall` for the given packages. `zap` also removes a cask's app data. A dry run
    /// reports the would-run lines and spawns no process.
    public static func uninstall(_ packages: [BrewPackage], zap: Bool, dryRun: Bool) -> Subprocess.Result {
        let formulae = packages.filter { $0.kind == .formula }.map(\.name)
        let casks = packages.filter { $0.kind == .cask }.map(\.name)
        guard !dryRun else {
            return wouldRun(formulae: formulae, casks: casks, verb: "uninstall", zap: zap)
        }
        var outs: [Subprocess.Result] = []
        if !formulae.isEmpty { outs.append(run(["uninstall", "--formula"] + formulae, timeout: 300)) }
        if !casks.isEmpty {
            outs.append(run(["uninstall", "--cask"] + (zap ? ["--zap"] : []) + casks, timeout: 300))
        }
        return combine(outs)
    }

    /// `brew cleanup`: removes old versions and the download cache. Returns the "freed
    /// approximately X" amount when brew reports one. A dry run runs no `brew` call.
    public static func cleanup(dryRun: Bool) -> (result: Subprocess.Result, freed: String?) {
        guard !dryRun else { return (wouldRun("brew cleanup"), nil) }
        let result = run(["cleanup"], timeout: 300)
        let freed = (result.out + "\n" + result.err).split(separator: "\n")
            .first { $0.contains("freed approximately") }
            .flatMap { line -> String? in
                guard let range = line.range(of: "approximately ") else { return nil }
                return line[range.upperBound...].split(separator: " ").first.map(String.init)
            }
        return (result, freed)
    }

    /// `brew update`. A dry run reports the command and spawns no process.
    public static func update(dryRun: Bool) -> Subprocess.Result {
        guard !dryRun else { return wouldRun("brew update") }
        return run(["update"], timeout: 300)
    }

    /// `brew upgrade` for the given packages, formulae then casks. A dry run reports the
    /// commands and spawns no process.
    public static func upgrade(_ packages: [BrewPackage], dryRun: Bool) -> Subprocess.Result {
        let formulae = packages.filter { $0.kind == .formula }.map(\.name)
        let casks = packages.filter { $0.kind == .cask }.map(\.name)
        guard !dryRun else {
            return wouldRun(formulae: formulae, casks: casks, verb: "upgrade")
        }
        var outs: [Subprocess.Result] = []
        if !formulae.isEmpty { outs.append(run(["upgrade", "--formula"] + formulae, timeout: 1800)) }
        if !casks.isEmpty { outs.append(run(["upgrade", "--cask"] + casks, timeout: 1800)) }
        return combine(outs)
    }

    /// One name from `brew search`.
    public struct SearchResult: Sendable, Hashable, Identifiable {
        public let name: String
        public let isCask: Bool
        public var id: String { (isCask ? "cask:" : "formula:") + name }
    }

    /// Names matching `query`, formulae then casks, plus a message when brew could not search.
    /// Read-only: `HOMEBREW_NO_AUTO_UPDATE` is already set, so it reads the local index only.
    public static func search(_ query: String) -> (results: [SearchResult], message: String?) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ([], nil) }
        func names(_ output: String) -> [String] {
            output.split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("==>") }
        }
        let formulae = run(["search", "--formula", trimmed])
        let casks = run(["search", "--cask", trimmed])
        let results =
            names(formulae.out).map { SearchResult(name: $0, isCask: false) }
            + names(casks.out).map { SearchResult(name: $0, isCask: true) }
        let failures = [formulae, casks].filter { !$0.ok }
        let message =
            results.isEmpty && !failures.isEmpty
            ? failures.map(\.message).joined(separator: "\n") : nil
        return (results, message)
    }

    /// `brew install` the given names, formulae then casks. A dry run reports the commands.
    public static func install(
        formulae: [String], casks: [String], dryRun: Bool
    ) -> Subprocess.Result {
        guard !dryRun else {
            return wouldRun(formulae: formulae, casks: casks, verb: "install")
        }
        var outs: [Subprocess.Result] = []
        if !formulae.isEmpty { outs.append(run(["install", "--formula"] + formulae, timeout: 1800)) }
        if !casks.isEmpty { outs.append(run(["install", "--cask"] + casks, timeout: 1800)) }
        return combine(outs)
    }

    /// `brew tap`. A dry run reports the command.
    public static func addTap(_ name: String, dryRun: Bool) -> Subprocess.Result {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dryRun else { return wouldRun("brew tap " + trimmed) }
        return run(["tap", trimmed], timeout: 300)
    }
}
