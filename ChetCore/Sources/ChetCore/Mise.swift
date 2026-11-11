import Foundation

public enum Mise {
    public struct Declared: Hashable, Sendable {
        public let name: String
        public let version: String

        public init(name: String, version: String) {
            self.name = name
            self.version = version
        }
    }

    public struct Detection: Sendable {
        public let configPath: URL
        public let configExists: Bool
        public let declared: [Declared]
        public let executable: String?

        public var available: Bool { !declared.isEmpty && executable != nil }

        public init(configPath: URL, configExists: Bool, declared: [Declared], executable: String?) {
            self.configPath = configPath
            self.configExists = configExists
            self.declared = declared
            self.executable = executable
        }
    }

    public struct Resolved: Hashable, Sendable, Decodable {
        public let version: String
        public let installPath: String?
        public let installed: Bool
        public let active: Bool

        private enum CodingKeys: String, CodingKey {
            case version
            case installPath = "install_path"
            case installed
            case active
        }

        public init(version: String, installPath: String?, installed: Bool, active: Bool) {
            self.version = version
            self.installPath = installPath
            self.installed = installed
            self.active = active
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decode(String.self, forKey: .version)
            installPath = try container.decodeIfPresent(String.self, forKey: .installPath)
            installed = try container.decodeIfPresent(Bool.self, forKey: .installed) ?? false
            active = try container.decodeIfPresent(Bool.self, forKey: .active) ?? false
        }
    }

    public struct Tool: Identifiable, Hashable, Sendable {
        public let name: String
        public let version: String
        public let requested: String
        public let resolved: String?
        public let installPath: String?
        public let active: Bool
        public let installed: Bool
        public let declared: Bool

        public var id: String { "\(name)@\(version)" }

        public init(
            name: String, version: String = "", requested: String, resolved: String? = nil,
            installPath: String?, active: Bool, installed: Bool, declared: Bool = false
        ) {
            self.name = name
            self.version = version
            self.requested = requested
            self.resolved = resolved
            self.installPath = installPath
            self.active = active
            self.installed = installed
            self.declared = declared
        }
    }

    public struct Snapshot: Sendable {
        public let tools: [Tool]
        public let configPath: String
        public let cachePath: String?
        public let error: String?

        public init(tools: [Tool], configPath: String, cachePath: String?, error: String?) {
            self.tools = tools
            self.configPath = configPath
            self.cachePath = cachePath
            self.error = error
        }
    }

    public static func detect(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        path: String = ProcessInfo.processInfo.environment["PATH"] ?? ""
    ) -> Detection {
        let configPath = home.appendingPathComponent(".config/mise/config.toml")
        let exists = FileManager.default.fileExists(atPath: configPath.path)
        let text = exists ? try? String(contentsOf: configPath, encoding: .utf8) : nil
        let declared = text.map(parseConfig) ?? []
        let executable = declared.isEmpty ? nil : resolveExecutable(home: home, path: path)
        return Detection(
            configPath: configPath, configExists: exists, declared: declared, executable: executable)
    }

    public static func parseConfig(_ text: String) -> [Declared] {
        var declared: [Declared] = []
        var inTools = false
        for statement in statements(text) {
            let line = statement.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("[") {
                inTools = tableName(line) == "tools"
                continue
            }
            guard inTools, let (name, value) = assignment(line) else { continue }
            for version in versions(value) {
                declared.append(Declared(name: name, version: version))
            }
        }
        return declared
    }

    public static func dataDirectory(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        path: String = ProcessInfo.processInfo.environment["PATH"] ?? "",
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        if let raw = environment["MISE_DATA_DIR"], let url = dataCandidate(raw, home: home) {
            return url
        }

        let configDirectory = home.appendingPathComponent(".config/mise")
        if let raw = settingsValue(
            "data_dir", at: configDirectory.appendingPathComponent("config.toml"),
            underSettings: true),
            let url = dataCandidate(raw, home: home)
        {
            return url
        }
        if let raw = settingsValue(
            "data_dir", at: configDirectory.appendingPathComponent("settings.toml"),
            underSettings: false),
            let url = dataCandidate(raw, home: home)
        {
            return url
        }

        for name in [".zshrc", ".zprofile", ".bashrc", ".bash_profile"] {
            for raw in shellValues(
                "MISE_DATA_DIR", at: home.appendingPathComponent(name), home: home)
            {
                if let url = dataCandidate(raw, home: home) { return url }
            }
        }

        if let scanned = scannedDataDirectory(home: home, environment: environment) {
            return scanned
        }

        let fallback = home.appendingPathComponent(".local/share/mise")
        return isDataDirectory(fallback) ? fallback : nil
    }

    public static func snapshot(_ detection: Detection) -> Snapshot {
        let configPath = detection.configPath.path
        guard let executable = detection.executable else {
            return Snapshot(
                tools: rows(declared: detection.declared, resolved: [:]),
                configPath: configPath, cachePath: nil, error: nil)
        }

        let home = detection.configPath
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let environment = invocationEnvironment(
            home: home, environment: ProcessInfo.processInfo.environment)

        var error: String?
        var resolved: [String: [Resolved]] = [:]
        let listing = runLogged(executable, ["ls", "--json"], env: environment, timeout: 20)
        if listing.ok, let parsed = parseResolved(listing.out) {
            resolved = parsed
        } else {
            error = listing.ok ? "Couldn't read mise's tool list." : "mise couldn't list its tools."
        }

        let cache = runLogged(executable, ["cache", "path"], env: environment, timeout: 20)
        let cachePath = cache.ok ? cache.out.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        if cachePath.isEmpty, error == nil {
            error = "mise couldn't report its cache directory."
        }

        return Snapshot(
            tools: rows(declared: detection.declared, resolved: resolved),
            configPath: configPath, cachePath: cachePath.isEmpty ? nil : cachePath, error: error)
    }

    private static func runLogged(
        _ executable: String, _ arguments: [String], env: [String: String],
        timeout: TimeInterval
    ) -> Subprocess.Result {
        let started = Date()
        let result = Subprocess.run(executable, arguments, env: env, timeout: timeout)
        VerboseLog.event(
            .info, .process, .processRun,
            .basename(.executable, Basename(path: executable)),
            .count(.argCount, arguments.count),
            .durationMS(.durationMS, Int(Date().timeIntervalSince(started) * 1_000)),
            .status(.status, result.status))
        return result
    }

    public static func parseResolved(_ json: String) -> [String: [Resolved]]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([String: [Resolved]].self, from: data)
    }

    public static func rows(declared: [Declared], resolved: [String: [Resolved]]) -> [Tool] {
        var requestedVersions: [String: [String]] = [:]
        for item in declared where !(requestedVersions[item.name] ?? []).contains(item.version) {
            requestedVersions[item.name, default: []].append(item.version)
        }

        let names = Set(requestedVersions.keys).union(resolved.keys)
        var tools: [Tool] = []
        for name in names {
            let versions = requestedVersions[name] ?? []
            let requested = versions.first ?? ""
            var installed = (resolved[name] ?? []).filter(\.installed).map { entry in
                Tool(
                    name: name, version: entry.version, requested: requested,
                    resolved: entry.version, installPath: entry.installPath,
                    active: entry.active, installed: true)
            }

            for version in versions {
                let match =
                    version == "latest"
                    ? installed.firstIndex(where: \.active) ?? installed.indices.first
                    : installed.firstIndex { $0.version == version }
                if let match {
                    let row = installed[match]
                    installed[match] = Tool(
                        name: row.name, version: row.version, requested: row.requested,
                        resolved: row.resolved, installPath: row.installPath,
                        active: row.active, installed: true, declared: true)
                } else {
                    tools.append(
                        Tool(
                            name: name, version: version, requested: requested,
                            installPath: nil, active: false, installed: false, declared: true))
                }
            }

            tools.append(contentsOf: installed)
        }

        return tools.sorted { lhs, rhs in
            if lhs.name != rhs.name { return lhs.name < rhs.name }
            if lhs.declared != rhs.declared { return lhs.declared }
            let order = versionOrder(lhs.version, rhs.version)
            if order != 0 { return order > 0 }
            return lhs.version > rhs.version
        }
    }

    private static func versionOrder(_ lhs: String, _ rhs: String) -> Int {
        let left = lhs.split(separator: ".", omittingEmptySubsequences: false)
        let right = rhs.split(separator: ".", omittingEmptySubsequences: false)
        for index in 0..<min(left.count, right.count) {
            let lhsPart = String(left[index])
            let rhsPart = String(right[index])
            if let lhsNumber = Int(lhsPart), let rhsNumber = Int(rhsPart) {
                if lhsNumber != rhsNumber { return lhsNumber > rhsNumber ? 1 : -1 }
            } else if lhsPart != rhsPart {
                return lhsPart > rhsPart ? 1 : -1
            }
        }
        if left.count == right.count { return 0 }
        return left.count > right.count ? 1 : -1
    }

    private static func invocationEnvironment(
        home: URL, environment: [String: String]
    ) -> [String: String] {
        var env = environment
        let configDirectory = home.appendingPathComponent(".config/mise")
        if directoryExists(configDirectory) {
            env["MISE_CONFIG_DIR"] = configDirectory.path
        }
        if let data = dataDirectory(home: home, path: env["PATH"] ?? "", environment: env) {
            env["MISE_DATA_DIR"] = data.path
        }
        return env
    }

    private static func dataCandidate(_ raw: String, home: URL) -> URL? {
        let expanded = expandHome(raw, home: home).trimmingCharacters(in: .whitespaces)
        guard !expanded.isEmpty else { return nil }
        let url =
            expanded.hasPrefix("/")
            ? URL(fileURLWithPath: expanded)
            : home.appendingPathComponent(expanded)
        return isDataDirectory(url) ? url : nil
    }

    private static func isDataDirectory(_ url: URL) -> Bool {
        directoryExists(url.appendingPathComponent("installs"))
    }

    private static func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }
        return isDirectory.boolValue
    }

    private static func settingsValue(
        _ key: String, at url: URL, underSettings: Bool
    ) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var inSettings = false
        var loose: String?
        for statement in statements(text) {
            let line = statement.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("[") {
                inSettings = tableName(line) == "settings"
                continue
            }
            guard let (name, value) = assignment(line), name == key,
                let raw = unquote(value)
            else { continue }
            if inSettings { return raw }
            if !underSettings, loose == nil { loose = raw }
        }
        return loose
    }

    private static func shellValues(_ key: String, at url: URL, home: URL) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var values: [String] = []
        for statement in statements(text) {
            var line = statement.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("export ") {
                line = String(line.dropFirst("export ".count))
                    .trimmingCharacters(in: .whitespaces)
            }
            guard let (name, value) = assignment(line), name == key,
                let text = shellWord(value)
            else { continue }
            values.append(expandHome(text, home: home))
        }
        return values
    }

    private static func shellWord(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let quoted = unquote(trimmed) { return quoted }
        let word = trimmed.prefix { !$0.isWhitespace }
        return word.isEmpty ? nil : String(word)
    }

    private static func expandHome(_ value: String, home: URL) -> String {
        value
            .replacingOccurrences(of: "${HOME}", with: home.path)
            .replacingOccurrences(of: "$HOME", with: home.path)
    }

    private static func scannedDataDirectory(
        home: URL, environment: [String: String]
    ) -> URL? {
        var candidates: [URL] = [
            home.appendingPathComponent("Development/sdks/mise"),
            home.appendingPathComponent("sdks/mise"),
            home.appendingPathComponent("mise"),
            home.appendingPathComponent(".mise"),
            home.appendingPathComponent("Library/Application Support/mise"),
        ]
        if let xdg = environment["XDG_DATA_HOME"], !xdg.isEmpty {
            candidates.append(URL(fileURLWithPath: xdg).appendingPathComponent("mise"))
        }
        let children =
            (try? FileManager.default.contentsOfDirectory(
                at: home, includingPropertiesForKeys: nil, options: [])) ?? []
        for child in children where directoryExists(child) {
            candidates.append(child.appendingPathComponent("mise"))
        }
        for candidate in candidates {
            if isDataDirectory(candidate) { return candidate }
        }
        return nil
    }

    private static func resolveExecutable(home: URL, path: String) -> String? {
        let local = home.appendingPathComponent(".local/bin/mise").path
        if isExecutableFile(local) { return local }
        for entry in path.split(separator: ":", omittingEmptySubsequences: false) {
            let directory = String(entry)
            guard !directory.isEmpty, (directory as NSString).isAbsolutePath else { continue }
            let candidate = (directory as NSString).appendingPathComponent("mise")
            if isExecutableFile(candidate) { return candidate }
        }
        return nil
    }

    private static func isExecutableFile(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
            !isDirectory.boolValue
        else { return false }
        return FileManager.default.isExecutableFile(atPath: path)
    }

    private static func statements(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        var depth = 0
        var quote: Character?
        var escaped = false
        var comment = false
        for ch in text {
            if comment {
                if ch == "\n" {
                    comment = false
                    if depth == 0 {
                        out.append(current)
                        current = ""
                    } else {
                        current.append(" ")
                    }
                }
                continue
            }
            if let q = quote {
                current.append(ch)
                if escaped {
                    escaped = false
                } else if ch == "\\" && q == "\"" {
                    escaped = true
                } else if ch == q {
                    quote = nil
                }
                continue
            }
            switch ch {
            case "\"", "'":
                quote = ch
                current.append(ch)
            case "#":
                comment = true
            case "[", "{":
                depth += 1
                current.append(ch)
            case "]", "}":
                depth = max(0, depth - 1)
                current.append(ch)
            case "\n":
                if depth == 0 {
                    out.append(current)
                    current = ""
                } else {
                    current.append(" ")
                }
            default:
                current.append(ch)
            }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty { out.append(current) }
        return out
    }

    private static func tableName(_ line: String) -> String? {
        guard line.hasPrefix("["), line.hasSuffix("]") else { return nil }
        let inner = line.dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
        if let quoted = unquote(inner) { return quoted }
        return inner.isEmpty ? nil : inner
    }

    private static func assignment(_ line: String) -> (String, String)? {
        var quote: Character?
        var escaped = false
        var depth = 0
        for (offset, ch) in line.enumerated() {
            if let q = quote {
                if escaped {
                    escaped = false
                } else if ch == "\\" && q == "\"" {
                    escaped = true
                } else if ch == q {
                    quote = nil
                }
                continue
            }
            switch ch {
            case "\"", "'":
                quote = ch
            case "[", "{":
                depth += 1
            case "]", "}":
                depth -= 1
            case "=" where depth == 0:
                let index = line.index(line.startIndex, offsetBy: offset)
                let key = line[..<index].trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: index)...].trimmingCharacters(in: .whitespaces)
                guard let name = keyName(key) else { return nil }
                return (name, value)
            default:
                break
            }
        }
        return nil
    }

    private static func keyName(_ text: String) -> String? {
        if let quoted = unquote(text) { return quoted }
        guard !text.isEmpty,
            text.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" })
        else { return nil }
        return text
    }

    private static func versions(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("[") {
            guard trimmed.hasSuffix("]") else { return [] }
            let body = trimmed.dropFirst().dropLast()
            return splitTopLevel(String(body), separator: ",").compactMap {
                unquote($0.trimmingCharacters(in: .whitespaces))
            }
        }
        if trimmed.hasPrefix("{") {
            guard trimmed.hasSuffix("}") else { return [] }
            let body = trimmed.dropFirst().dropLast()
            for field in splitTopLevel(String(body), separator: ",") {
                guard let (key, value) = assignment(field.trimmingCharacters(in: .whitespaces)),
                    key == "version"
                else { continue }
                if let version = unquote(value) { return [version] }
            }
            return []
        }
        return unquote(trimmed).map { [$0] } ?? []
    }

    private static func splitTopLevel(_ text: String, separator: Character) -> [String] {
        var parts: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false
        var depth = 0
        for ch in text {
            if let q = quote {
                current.append(ch)
                if escaped {
                    escaped = false
                } else if ch == "\\" && q == "\"" {
                    escaped = true
                } else if ch == q {
                    quote = nil
                }
                continue
            }
            if ch == "\"" || ch == "'" {
                quote = ch
                current.append(ch)
            } else if ch == "[" || ch == "{" {
                depth += 1
                current.append(ch)
            } else if ch == "]" || ch == "}" {
                depth -= 1
                current.append(ch)
            } else if ch == separator && depth == 0 {
                parts.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        parts.append(current)
        return parts
    }

    private static func unquote(_ text: String) -> String? {
        guard let (value, rest) = string(text),
            rest.trimmingCharacters(in: .whitespaces).isEmpty
        else { return nil }
        return value
    }

    private static func string(_ text: String) -> (String, String)? {
        guard let first = text.first, first == "\"" || first == "'" else { return nil }
        var value = ""
        var escaped = false
        var index = text.index(after: text.startIndex)
        while index < text.endIndex {
            let ch = text[index]
            if first == "\"" {
                if escaped {
                    value.append(unescape(ch))
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    return (value, String(text[text.index(after: index)...]))
                } else {
                    value.append(ch)
                }
            } else {
                if ch == "'" { return (value, String(text[text.index(after: index)...])) }
                value.append(ch)
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func unescape(_ ch: Character) -> Character {
        switch ch {
        case "n": "\n"
        case "t": "\t"
        case "r": "\r"
        default: ch
        }
    }
}
