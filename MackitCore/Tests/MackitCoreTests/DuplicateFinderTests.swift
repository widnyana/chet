import Darwin
import Foundation
import Testing

@testable import MackitCore

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
}
