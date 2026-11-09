import Darwin
import Foundation

@testable import ChetCore

/// A fresh temp folder used as a fake home directory in tests.
struct TempDir {
    let url: URL

    init() throws {
        let candidate = FileManager.default.temporaryDirectory
            .appendingPathComponent("chet-\(UUID().uuidString)")
        // Canonicalize with realpath(3): FileWalker's enumerator yields fully resolved paths
        // (e.g. /private/var/...), and Foundation's resolvingSymlinksInPath does not resolve
        // the /var symlink, which would break prefix comparisons in tests.
        // The directory must exist before realpath(3) can resolve it.
        try FileManager.default.createDirectory(
            at: candidate, withIntermediateDirectories: true)
        let canonical =
            candidate.path.withCString { realpath($0, nil) }.map {
                String(cString: $0)
            } ?? candidate.path
        url = URL(fileURLWithPath: canonical)
    }

    var policy: SafetyPolicy { SafetyPolicy(home: url) }

    @discardableResult
    func file(_ relative: String, bytes: Int, fill: UInt8 = 1) throws -> URL {
        let target = url.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: fill, count: bytes).write(to: target)
        return target
    }

    @discardableResult
    func text(_ relative: String, _ contents: String) throws -> URL {
        let target = url.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: target)
        return target
    }
}
