import Foundation

/// The Go toolchain on this Mac and the module cache it keeps.
public enum GoModules {
    public enum Source: String, Sendable { case path, homebrew, native, mise, gvm, shim }

    public struct Location: Sendable, Equatable {
        public let executable: String
        public let source: Source
    }

    public struct Info: Sendable, Equatable {
        public let executable: String
        public let source: Source
        public let version: String
        public let cachePath: String
        public let bytes: Int64
        public let moduleCount: Int
    }

    public static func miseLocation(from tools: [Mise.Tool]) -> Location? {
        let go = tools.filter { $0.name == "go" && $0.installPath != nil }
        let selected = go.first(where: \.active) ?? go.first(where: \.installed) ?? go.first
        guard let installPath = selected?.installPath else { return nil }
        return Location(executable: installPath + "/bin/go", source: .mise)
    }

    /// First executable in discovery order: mise, PATH, mise installs, GVM, mise shims, fixed
    /// Homebrew and native locations.
    public static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        exists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        run: (String, [String]) -> Subprocess.Result = { Subprocess.run($0, $1, timeout: 10) },
        miseTools: [Mise.Tool]? = nil
    ) -> Location? {
        let home = environment["HOME"] ?? NSHomeDirectory()
        let directories = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }

        let tools: [Mise.Tool]
        if let miseTools {
            tools = miseTools
        } else {
            let detection = Mise.detect()
            tools = detection.available ? Mise.snapshot(detection).tools : []
        }
        if let location = miseLocation(from: tools) {
            return location
        }

        let search =
            directories
            + ["/usr/local/bin", "/opt/homebrew/bin", "/usr/bin", "/bin", home + "/.local/bin"]
        if let executable = search.map({ $0 + "/go" }).first(where: exists) {
            return Location(executable: executable, source: pathSource(executable))
        }

        var installRoots: [String] = []
        if let dataDirectory = environment["MISE_DATA_DIR"], !dataDirectory.isEmpty {
            installRoots.append(dataDirectory + "/installs/go")
        }
        installRoots.append(home + "/.local/share/mise/installs/go")
        installRoots.append(home + "/.mise/installs/go")
        for root in installRoots {
            if let executable = highestInstall(in: root, exists: exists) {
                return Location(executable: executable, source: .mise)
            }
        }

        if let executable = highestInstall(in: home + "/.gvm/gos", exists: exists) {
            return Location(executable: executable, source: .gvm)
        }
        let gvmBinary = home + "/.gvm/bin/go"
        if exists(gvmBinary) {
            return Location(executable: gvmBinary, source: .gvm)
        }

        for shim in [home + "/.local/share/mise/shims/go", home + "/.mise/shims/go"]
        where exists(shim) {
            return Location(executable: shim, source: .shim)
        }

        let fixed: [(String, Source)] = [
            ("/opt/homebrew/bin/go", .homebrew),
            ("/opt/homebrew/opt/go/bin/go", .homebrew),
            ("/usr/local/bin/go", .homebrew),
            ("/usr/local/go/bin/go", .native),
            ("/usr/bin/go", .native),
        ]
        for (path, source) in fixed where exists(path) {
            return Location(executable: path, source: source)
        }
        return nil
    }

    /// `KEY=value` lines from `go env A B`, blank and non-assignment lines dropped.
    public static func parseEnv(_ output: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let text = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let separator = text.firstIndex(of: "=") else { continue }
            let key = text[..<separator].trimmingCharacters(in: .whitespaces)
            let value = text[text.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            values[key] = value
        }
        return values
    }

    /// GOMODCACHE the go binary reports, then the environment, then GOPATH, then `~/go/pkg/mod`;
    /// output with no assignment is a bare path.
    public static func cachePath(
        for executable: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        run: (String, [String]) -> Subprocess.Result = { Subprocess.run($0, $1, timeout: 10) }
    ) -> String {
        let output = run(executable, ["env", "GOMODCACHE", "GOPATH"]).out
        let reported = parseEnv(output)
        if let cache = reported["GOMODCACHE"], !cache.isEmpty { return cache }
        if !output.contains("=") {
            let bare = output.split(whereSeparator: \.isNewline)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
            if let bare { return bare }
        }
        if let cache = environment["GOMODCACHE"], !cache.isEmpty { return cache }
        if let gopath = reported["GOPATH"], !gopath.isEmpty { return gopath + "/pkg/mod" }
        if let gopath = environment["GOPATH"], !gopath.isEmpty { return gopath + "/pkg/mod" }
        return home(environment) + "/go/pkg/mod"
    }

    private static func runLogged(
        _ executable: String, _ arguments: [String], timeout: TimeInterval
    ) -> Subprocess.Result {
        let started = Date()
        let result = Subprocess.run(executable, arguments, timeout: timeout)
        VerboseLog.event(
            .info, .process, .processRun,
            .basename(.executable, Basename(path: executable)),
            .count(.argCount, arguments.count),
            .durationMS(.durationMS, Int(Date().timeIntervalSince(started) * 1_000)),
            .status(.status, result.status))
        return result
    }

    /// Runs `go version`, resolves the cache path, then measures the cache in one walk.
    public static func measure(_ location: Location) -> Info {
        let versionResult = runLogged(location.executable, ["version"], timeout: 10)
        let reported = versionResult.out.trimmingCharacters(in: .whitespacesAndNewlines)
        let version = versionResult.ok && !reported.isEmpty ? reported : "Go"
        let cache = cachePath(for: location.executable)
        var totals = Totals()
        walk(URL(fileURLWithPath: cache), depth: 0, inCache: false, into: &totals)
        return Info(
            executable: location.executable, source: location.source, version: version,
            cachePath: cache, bytes: totals.bytes, moduleCount: totals.modules)
    }

    /// `go clean -modcache`. A dry run reports the command and spawns nothing.
    public static func clean(_ location: Location, dryRun: Bool) -> Subprocess.Result {
        guard !dryRun else {
            return Subprocess.Result(
                status: 0, out: "Would run: \(location.executable) clean -modcache", err: "")
        }
        return runLogged(location.executable, ["clean", "-modcache"], timeout: 600)
    }

    private struct Totals {
        var bytes: Int64 = 0
        var modules: Int = 0
    }

    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey,
    ]
    private static let keySet: Set<URLResourceKey> = Set(keys)

    private static func walk(_ url: URL, depth: Int, inCache: Bool, into totals: inout Totals) {
        guard let values = try? url.resourceValues(forKeys: keySet) else { return }
        if values.isSymbolicLink == true { return }
        guard values.isDirectory == true else {
            guard values.isRegularFile == true else { return }
            totals.bytes += Int64(values.totalFileAllocatedSize ?? 0)
            return
        }
        if depth > 0, !inCache, url.lastPathComponent.contains("@") {
            totals.modules += 1
        }
        let insideCache = inCache || (depth == 1 && url.lastPathComponent == "cache")
        let children =
            (try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: keys, options: [])) ?? []
        for child in children {
            autoreleasepool {
                walk(child, depth: depth + 1, inCache: insideCache, into: &totals)
            }
        }
    }

    /// `<root>/<version>/bin/go` with the highest numeric version, or nil when none is executable.
    private static func highestInstall(in root: String, exists: (String) -> Bool) -> String? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
        let installed = names.map { (version: $0, executable: root + "/" + $0 + "/bin/go") }
            .filter { exists($0.executable) }
        return installed.max { compareVersions($0.version, $1.version) < 0 }?.executable
    }

    private static func compareVersions(_ lhs: String, _ rhs: String) -> Int {
        let left = lhs.split(separator: ".")
        let right = rhs.split(separator: ".")
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? numericPrefix(left[index]) : 0
            let b = index < right.count ? numericPrefix(right[index]) : 0
            if a != b { return a < b ? -1 : 1 }
        }
        return 0
    }

    private static func numericPrefix(_ component: Substring) -> Int {
        Int(component.drop { !$0.isNumber }.prefix { $0.isNumber }) ?? 0
    }

    private static func pathSource(_ executable: String) -> Source {
        executable.hasPrefix("/opt/homebrew/") || executable.hasPrefix("/usr/local/")
            ? .homebrew : .path
    }

    private static func home(_ environment: [String: String]) -> String {
        environment["HOME"] ?? NSHomeDirectory()
    }
}
