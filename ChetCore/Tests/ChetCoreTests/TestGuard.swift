import Darwin
import Foundation
import Testing

@testable import ChetCore

enum TestGuardError: Error, Equatable, CustomStringConvertible {
    case dryRunMissing
    case scratchRootInvalid(String)
    case pathOutsideScratchRoot(String)
    case mutationOutsideScratchRoot(String)

    var description: String {
        switch self {
        case .dryRunMissing: "tests require DRY_RUN=1"
        case .scratchRootInvalid(let path):
            "scratch root is not absolute or does not exist: \(path)"
        case .pathOutsideScratchRoot(let path):
            "scratch root does not resolve under /var/folders or /tmp: \(path)"
        case .mutationOutsideScratchRoot(let path):
            "mutation outside the scratch root: \(path)"
        }
    }
}

extension TestGuardError: LocalizedError {
    var errorDescription: String? { description }
}

enum TestGuard {
    static var userPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            home + "/Library/Application Support",
            home + "/Library/Preferences",
            home + "/Library/Logs/chet",
            home + "/Library/Caches/id.web.widnyana.chet",
            home + "/.Trash",
        ]
    }

    static func requireDryRun(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        let raw = environment["DRY_RUN"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard ["1", "true"].contains(raw.lowercased()) else {
            throw TestGuardError.dryRunMissing
        }
    }

    static func requireScratchRoot(_ path: String) throws -> URL {
        guard path.hasPrefix("/") else { throw TestGuardError.scratchRootInvalid(path) }
        guard let resolved = path.withCString({ realpath($0, nil) }) else {
            throw TestGuardError.scratchRootInvalid(path)
        }
        defer { free(resolved) }
        let canonical = String(cString: resolved)
        let bases = ["/var/folders", "/private/var/folders", "/tmp", "/private/tmp"]
        let containerTemporary =
            canonical.contains("/Library/Containers/") && canonical.contains("/Data/tmp/")
        guard containerTemporary || bases.contains(where: { canonical.hasPrefix($0 + "/") }) else {
            throw TestGuardError.pathOutsideScratchRoot(path)
        }
        return URL(fileURLWithPath: canonical, isDirectory: true)
    }

    static func snapshot(of paths: [String]) -> [String: String] {
        var entries: [String: String] = [:]
        for path in paths {
            record(path, into: &entries)
        }
        return entries
    }

    static func assertNoMutation(
        outside root: URL, during body: () throws -> Void
    ) throws {
        let scratch = try requireScratchRoot(root.path)
        let parent = scratch.deletingLastPathComponent().path
        let before = snapshotOutside(root: scratch, parent: parent)
        let userBefore = userSnapshot()
        try body()
        if let changed =
            firstChange(from: before, to: snapshotOutside(root: scratch, parent: parent))
            ?? firstChange(from: userBefore, to: userSnapshot())
        {
            throw TestGuardError.mutationOutsideScratchRoot(changed)
        }
    }

    private static func snapshotOutside(root: URL, parent: String) -> [String: String] {
        var entries: [String: String] = [:]
        recordOutside(parent, root: root.path, into: &entries)
        return entries
    }

    private static func recordOutside(
        _ path: String, root: String, into entries: inout [String: String]
    ) {
        guard path != root, !path.hasPrefix(root + "/") else { return }
        guard recordState(path, into: &entries) else { return }
        guard let children = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            return
        }
        for child in children {
            recordOutside(
                URL(fileURLWithPath: path).appendingPathComponent(child).path, root: root,
                into: &entries)
        }
    }

    private static func userSnapshot() -> [String: String] {
        var entries: [String: String] = [:]
        for path in userPaths {
            guard recordState(path, into: &entries) else { continue }
            guard let children = try? FileManager.default.contentsOfDirectory(atPath: path)
            else { continue }
            for child in children {
                let childPath = URL(fileURLWithPath: path).appendingPathComponent(child).path
                _ = recordState(childPath, into: &entries)
            }
        }
        return entries
    }

    private static func record(_ path: String, into entries: inout [String: String]) {
        guard recordState(path, into: &entries) else { return }
        guard let children = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            return
        }
        for child in children {
            record(
                URL(fileURLWithPath: path).appendingPathComponent(child).path, into: &entries)
        }
    }

    private static func recordState(
        _ path: String, into entries: inout [String: String]
    ) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
            entries[path] = "missing"
            return false
        }
        guard attributes[.type] as? FileAttributeType == .typeDirectory else {
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            entries[path] = "file:\(size):\(modified)"
            return false
        }
        entries[path] = "dir"
        return true
    }

    private static func firstChange(
        from before: [String: String], to after: [String: String]
    ) -> String? {
        let paths = Set(before.keys).union(after.keys).sorted()
        return paths.first { before[$0] != after[$0] }
    }
}

struct DryRunGuardTests {
    @Test func suiteRequiresDryRun() throws {
        try TestGuard.requireDryRun()
    }
}
