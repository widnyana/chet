import Darwin
import Foundation

public struct TestPaths: Sendable, Equatable {
    public static let rootVariable = "CHET_UITEST_ROOT"

    public let root: URL
    public let applicationSupport: URL
    public let preferences: URL
    public let logs: URL
    public let caches: URL
    public let trash: URL
    public let temporary: URL

    public init(root: URL) {
        self.root = root
        applicationSupport = root.appendingPathComponent("Application Support", isDirectory: true)
        preferences = root.appendingPathComponent("Preferences", isDirectory: true)
        logs = root.appendingPathComponent("Logs", isDirectory: true)
        caches = root.appendingPathComponent("Caches", isDirectory: true)
        trash = root.appendingPathComponent("Trash", isDirectory: true)
        temporary = root.appendingPathComponent("Temporary", isDirectory: true)
    }

    public var directories: [URL] {
        [applicationSupport, preferences, logs, caches, trash, temporary]
    }

    public static func production(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        temporary: URL = FileManager.default.temporaryDirectory
    ) -> TestPaths {
        TestPaths(
            root: home,
            applicationSupport: home.appendingPathComponent("Library/Application Support", isDirectory: true),
            preferences: home.appendingPathComponent("Library/Preferences", isDirectory: true),
            logs: home.appendingPathComponent("Library/Logs/chet", isDirectory: true),
            caches: home.appendingPathComponent("Library/Caches", isDirectory: true),
            trash: home.appendingPathComponent(".Trash", isDirectory: true),
            temporary: temporary)
    }

    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> TestPaths? {
        guard let raw = environment[rootVariable], raw.hasPrefix("/") else { return nil }
        let components = raw.split(separator: "/")
        guard !components.isEmpty, components.allSatisfy({ $0 != "." && $0 != ".." }) else { return nil }
        guard let canonical = canonicalPath(raw) else { return nil }
        if let home = canonicalPath(FileManager.default.homeDirectoryForCurrentUser.path),
            isWithin(canonical, home)
        {
            return nil
        }
        guard temporaryBases.contains(where: { isDescendant(canonical, of: $0) }) else { return nil }
        return TestPaths(root: URL(fileURLWithPath: canonical, isDirectory: true))
    }

    public static func makeScratch(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> TestPaths? {
        guard let paths = resolve(environment: environment) else { return nil }
        let fileManager = FileManager.default
        let ownerOnly: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
        do {
            try fileManager.createDirectory(
                at: paths.root, withIntermediateDirectories: true, attributes: ownerOnly)
            try fileManager.setAttributes(ownerOnly, ofItemAtPath: paths.root.path)
            for directory in paths.directories {
                try fileManager.createDirectory(
                    at: directory, withIntermediateDirectories: true, attributes: ownerOnly)
                try fileManager.setAttributes(ownerOnly, ofItemAtPath: directory.path)
            }
        } catch {
            return nil
        }
        return paths
    }

    private init(
        root: URL, applicationSupport: URL, preferences: URL, logs: URL, caches: URL, trash: URL,
        temporary: URL
    ) {
        self.root = root
        self.applicationSupport = applicationSupport
        self.preferences = preferences
        self.logs = logs
        self.caches = caches
        self.trash = trash
        self.temporary = temporary
    }

    private static let temporaryBases: [String] = ["/tmp", FileManager.default.temporaryDirectory.path]
        .compactMap(canonicalPath)

    private static func canonicalPath(_ path: String) -> String? {
        var existing = URL(fileURLWithPath: path, isDirectory: true)
        var missing: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path) {
            guard existing.path != "/" else { return nil }
            missing.append(existing.lastPathComponent)
            existing.deleteLastPathComponent()
        }
        guard let resolved = realPath(existing.path) else { return nil }
        var url = URL(fileURLWithPath: resolved, isDirectory: true)
        for component in missing.reversed() {
            url.appendPathComponent(component, isDirectory: true)
        }
        return url.path
    }

    private static func realPath(_ path: String) -> String? {
        guard let buffer = path.withCString({ realpath($0, nil) }) else { return nil }
        defer { free(buffer) }
        return String(cString: buffer)
    }

    private static func isWithin(_ path: String, _ base: String) -> Bool {
        path == base || isDescendant(path, of: base)
    }

    private static func isDescendant(_ path: String, of base: String) -> Bool {
        base == "/" ? path != "/" : path.hasPrefix(base + "/")
    }
}
