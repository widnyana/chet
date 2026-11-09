import Darwin
import Foundation
import Testing

@testable import ChetCore

struct DuplicateFinderTests {
    private let size = 2_000_000

    @discardableResult
    private func write(_ data: Data, _ relative: String, in dir: TempDir) throws -> URL {
        let target = dir.url.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: target)
        return target
    }

    private func setMTime(_ url: URL, daysAgo: Double) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-daysAgo * 86_400)], ofItemAtPath: url.path)
    }

    @Test func threeCopiesFormOneGroup() throws {
        let dir = try TempDir()
        for folder in ["a", "b", "c"] { try dir.file("\(folder)/photo.raw", bytes: size, fill: 7) }
        let groups = try DuplicateFinder(policy: dir.policy).find(in: [dir.url])
        #expect(groups.count == 1)
        #expect(groups.first?.duplicates.count == 2)
        #expect((groups.first?.reclaimableBytes ?? 0) >= Int64(2 * size))
    }

    @Test func findOnWalkedEntriesMatchesFindOnRoots() throws {
        let dir = try TempDir()
        for folder in ["a", "b", "c"] { try dir.file("\(folder)/same", bytes: size, fill: 4) }
        try dir.file("other", bytes: size, fill: 5)
        let finder = DuplicateFinder(policy: dir.policy)
        var walked: [WalkEntry] = []
        try FileWalker(policy: dir.policy).walk(dir.url) { walked.append($0) }
        let fromEntries = try finder.find(entries: walked)
        let fromRoots = try finder.find(in: [dir.url])
        #expect(fromEntries.count == 1)
        #expect(fromEntries.map(\.digest) == fromRoots.map(\.digest))
        #expect(fromEntries.first?.duplicates.count == 2)
    }

    @Test func differentLastByteIsNotDuplicate() throws {
        let dir = try TempDir()
        var data = Data(repeating: 7, count: size)
        try write(data, "a", in: dir)
        data[size - 1] = 9
        try write(data, "b", in: dir)
        #expect(try DuplicateFinder(policy: dir.policy).find(in: [dir.url]).isEmpty)
    }

    @Test func differentMiddleIsNotDuplicate() throws {
        let dir = try TempDir()
        var data = Data(repeating: 7, count: size)
        try write(data, "a", in: dir)
        data[size / 2] = 9
        try write(data, "b", in: dir)
        #expect(try DuplicateFinder(policy: dir.policy).find(in: [dir.url]).isEmpty)
    }

    @Test func hardLinkIsNotDuplicate() throws {
        let dir = try TempDir()
        let a = try dir.file("a", bytes: size)
        #expect(link(a.path, dir.url.appendingPathComponent("b").path) == 0)
        #expect(try DuplicateFinder(policy: dir.policy).find(in: [dir.url]).isEmpty)
    }

    @Test func apfsCloneIsNotDuplicate() throws {
        let dir = try TempDir()
        let a = try dir.file("a", bytes: size)
        #expect(clonefile(a.path, dir.url.appendingPathComponent("b").path, 0) == 0)
        #expect(try DuplicateFinder(policy: dir.policy).find(in: [dir.url]).isEmpty)
    }

    @Test func filesUnderMinSizeAreIgnored() throws {
        let dir = try TempDir()
        try dir.file("a", bytes: 500_000)
        try dir.file("b", bytes: 500_000)
        #expect(try DuplicateFinder(policy: dir.policy).find(in: [dir.url]).isEmpty)
    }

    @Test func oldestCopyIsKeeper() throws {
        let dir = try TempDir()
        let old = try dir.file("old/x", bytes: size)
        try dir.file("new/x", bytes: size)
        try setMTime(old, daysAgo: 10)
        let group = try #require(try DuplicateFinder(policy: dir.policy).find(in: [dir.url]).first)
        #expect(group.keeper.url.path == old.path)
    }

    @Test func keepFolderWinsOverOldest() throws {
        let dir = try TempDir()
        let old = try dir.file("old/x", bytes: size)
        let kept = try dir.file("keep/x", bytes: size)
        try setMTime(old, daysAgo: 10)
        var finder = DuplicateFinder(policy: dir.policy)
        finder.keepFolders = [dir.url.appendingPathComponent("keep")]
        let group = try #require(try finder.find(in: [dir.url]).first)
        #expect(group.keeper.url.path == kept.path)
        #expect(group.duplicates.map(\.url.path) == [old.path])
    }

    @Test func cancellationThrows() async throws {
        let dir = try TempDir()
        for folder in ["a", "b"] { try dir.file("\(folder)/x", bytes: size) }
        let finder = DuplicateFinder(policy: dir.policy)
        let task = Task { () throws -> [DuplicateGroup] in
            withUnsafeCurrentTask { $0?.cancel() }
            return try finder.find(in: [dir.url])
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    // MARK: DuplicateScope

    @Test func standardScopeSkipsRegenerableAndTempFolders() throws {
        let dir = try TempDir()
        try dir.file("Documents/proj/node_modules/pkg/lib", bytes: size)
        try dir.file("Documents/proj/target/lib", bytes: size)
        try dir.file("Documents/.gradle/v1/lib", bytes: size)
        try dir.file("Pictures/.cache/stuff/lib", bytes: size)
        try dir.file("Music/tmp/scratch/lib", bytes: size)
        try dir.file("Pictures/keep/lib", bytes: size)
        var walked: [WalkEntry] = []
        try FileWalker(policy: dir.policy).walk(dir.url) { walked.append($0) }

        let standard = DuplicateScope.filter(walked, scope: .standard)
        #expect(standard.count == 1)
        #expect(standard[0].url.path.hasSuffix("Pictures/keep/lib"))

        // Opting in is exactly the unfiltered walk.
        #expect(DuplicateScope.filter(walked, scope: .everything).count == walked.count)

        // The standard walk finds nothing to hash; the everything walk finds the pair
        // (or more) among the skipped copies.
        #expect(try DuplicateFinder(policy: dir.policy).find(entries: standard).isEmpty)
        #expect(try DuplicateFinder(policy: dir.policy).find(entries: walked).count >= 1)
    }

    @Test func scopeMatchesWholeComponentsOnly() throws {
        let dir = try TempDir()
        try dir.file("Documents/temp.txt", bytes: size)
        try dir.file("Documents/template/lib", bytes: size)
        var walked: [WalkEntry] = []
        try FileWalker(policy: dir.policy).walk(dir.url) { walked.append($0) }
        let standard = DuplicateScope.filter(walked, scope: .standard)
        // "temp.txt" and the "template" folder share no skipped component; substring
        // matching would wrongly drop them.
        #expect(standard.count == walked.count)
    }

    @Test func scopeSkipsToolStateDirs() throws {
        let dir = try TempDir()
        try dir.file("Development/app/.terraform/providers/x", bytes: size)
        try dir.file("Development/app/.terragrunt-cache/hash/main.tf", bytes: size)
        var walked: [WalkEntry] = []
        try FileWalker(policy: dir.policy).walk(dir.url) { walked.append($0) }
        #expect(!walked.isEmpty)
        #expect(DuplicateScope.filter(walked, scope: .standard).isEmpty)
    }

    @Test func buildDirRuleSharesTheRegenerableNames() {
        let rule = Rule.catalog.first { $0.id == "dev-garbage" }
        #expect(rule?.recursiveNames == DuplicateScope.regenerableNames)
    }
}
