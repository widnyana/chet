import Foundation
import Testing

@testable import ChetCore

struct CleanerBatchTests {
    private func item(_ url: URL) throws -> ScanItem {
        let stamp = try #require(FileStamp.read(url))
        return ScanItem(
            url: url, categoryID: "test", risk: .safe, mode: .permanent,
            reclaimableBytes: stamp.size, stamp: stamp)
    }

    @Test func emptyBatchIsRefused() throws {
        let dir = try TempDir()
        let report = BatchGuard.validate([], policy: dir.policy, roots: [dir.url])
        #expect(report.refusal == .batchEmpty)
        #expect(report.accepted.isEmpty)
    }

    @Test func oversizedBatchIsRefused() throws {
        let dir = try TempDir()
        let file = try dir.file("cache/x", bytes: 10)
        let one = try item(file)
        let report = BatchGuard.validate(
            Array(repeating: one, count: BatchGuard.maxItems + 1), policy: dir.policy, roots: [dir.url])
        #expect(report.refusal == .batchTooLarge)
        #expect(report.accepted.isEmpty)
    }

    @Test func relativePathIsMalformed() throws {
        let dir = try TempDir()
        let relative = try #require(URL(string: "relative/path"))
        let report = BatchGuard.validate(paths: [relative], policy: dir.policy, roots: [dir.url])
        #expect(report.refusal == .batchMalformed)
        #expect(report.rejected.first?.url == relative)
    }

    @Test func rootPathIsMalformed() throws {
        let dir = try TempDir()
        let report = BatchGuard.validate(
            paths: [URL(fileURLWithPath: "/")], policy: dir.policy, roots: [dir.url])
        #expect(report.refusal == .batchMalformed)
    }

    @Test func parentComponentIsMalformed() throws {
        let dir = try TempDir()
        let path = dir.url.appendingPathComponent("cache/../x")
        let report = BatchGuard.validate(paths: [path], policy: dir.policy, roots: [dir.url])
        #expect(report.refusal == .batchMalformed)
    }

    @Test func pathOutsideEveryRootIsRefused() throws {
        let dir = try TempDir()
        let other = try TempDir()
        let file = try other.file("x", bytes: 10)
        let report = BatchGuard.validate(paths: [file], policy: dir.policy, roots: [dir.url])
        #expect(report.refusal == .batchOutsideRoot)
        #expect(report.rejected.first?.url == file)
    }

    @Test func policyDeniedPathIsRefusedWithItsReason() throws {
        let dir = try TempDir()
        try dir.file("Library/Caches/a", bytes: 10)
        let caches = dir.url.appendingPathComponent("Library/Caches")
        let report = BatchGuard.validate(paths: [caches], policy: dir.policy, roots: [dir.url])
        #expect(report.refusal == .containerFolder)
        #expect(report.rejected.first?.reason == .containerFolder)
    }

    @Test func cleanBatchIsAccepted() throws {
        let dir = try TempDir()
        let first = try dir.file("cache/a", bytes: 10)
        let second = try dir.file("cache/b", bytes: 20)
        let items = [try item(first), try item(second)]
        let report = BatchGuard.validate(items, policy: dir.policy, roots: [dir.url])
        #expect(report.refusal == nil)
        #expect(report.accepted.map(\.url) == [first, second])
        #expect(report.rejected.isEmpty)
    }

    @Test func rootsCoverTheCatalogForAnEmptyScope() throws {
        let dir = try TempDir()
        let roots = BatchGuard.roots(for: .everywhere, rules: Rule.catalog, home: dir.url, externalRoots: [])
        let paths = Set(roots.map(\.path))
        for rule in Rule.catalog {
            for root in rule.roots {
                let expected = root.hasPrefix("/") ? root : dir.url.appendingPathComponent(root).path
                #expect(paths.contains(URL(fileURLWithPath: expected).standardizedFileURL.path))
            }
        }
        #expect(paths.contains(dir.url.standardizedFileURL.path))
        #expect(paths.contains("/Applications"))
        #expect(paths.contains(dir.url.appendingPathComponent("Applications").standardizedFileURL.path))
    }

    @Test func rootsFollowTheScopeCategories() throws {
        let dir = try TempDir()
        let scope = ScanScope(categories: ["browser"])
        let roots = BatchGuard.roots(for: scope, rules: Rule.catalog, home: dir.url, externalRoots: [])
        let paths = Set(roots.map(\.path))
        for root in Rule.catalog.filter({ $0.category == "browser" }).flatMap(\.roots) {
            let expected = root.hasPrefix("/") ? root : dir.url.appendingPathComponent(root).path
            #expect(paths.contains(URL(fileURLWithPath: expected).standardizedFileURL.path))
        }
        let caches = dir.url.appendingPathComponent("Library/Caches").standardizedFileURL.path
        #expect(!paths.contains(caches))
    }
}
