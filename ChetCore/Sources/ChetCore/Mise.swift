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
        public let requested: String
        public let resolved: String?
        public let installPath: String?
        public let active: Bool
        public let installed: Bool

        public var id: String { "\(name)@\(requested)" }

        public init(
            name: String, requested: String, resolved: String?, installPath: String?,
            active: Bool, installed: Bool
        ) {
            self.name = name
            self.requested = requested
            self.resolved = resolved
            self.installPath = installPath
            self.active = active
            self.installed = installed
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

    public static func snapshot(_ detection: Detection) -> Snapshot {
        let configPath = detection.configPath.path
        guard let executable = detection.executable else {
            return Snapshot(
                tools: merge(declared: detection.declared, resolved: [:]),
                configPath: configPath, cachePath: nil, error: nil)
        }

        var error: String?
        var resolved: [String: [Resolved]] = [:]
        let listing = Subprocess.run(executable, ["ls", "--json"], timeout: 20)
        if listing.ok, let parsed = parseResolved(listing.out) {
            resolved = parsed
        } else {
            error = listing.ok ? "Couldn't read mise's tool list." : "mise couldn't list its tools."
        }

        let cache = Subprocess.run(executable, ["cache", "path"], timeout: 20)
        let cachePath = cache.ok ? cache.out.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        if cachePath.isEmpty, error == nil {
            error = "mise couldn't report its cache directory."
        }

        return Snapshot(
            tools: merge(declared: detection.declared, resolved: resolved),
            configPath: configPath, cachePath: cachePath.isEmpty ? nil : cachePath, error: error)
    }

    public static func parseResolved(_ json: String) -> [String: [Resolved]]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([String: [Resolved]].self, from: data)
    }

    public static func merge(declared: [Declared], resolved: [String: [Resolved]]) -> [Tool] {
        let tools = declared.map { row -> Tool in
            let candidates = (resolved[row.name] ?? []).filter(\.installed)
            let match =
                candidates.first { $0.version == row.version }
                ?? candidates.first(where: \.active)
                ?? candidates.first
            return Tool(
                name: row.name, requested: row.version, resolved: match?.version,
                installPath: match?.installPath, active: match?.active ?? false,
                installed: match != nil)
        }
        return tools.sorted { ($0.name, $0.requested) < ($1.name, $1.requested) }
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
