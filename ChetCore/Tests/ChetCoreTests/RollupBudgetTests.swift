import Foundation
import Testing

@testable import ChetCore

final class UpdateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [URL] = []

    func append(_ url: URL) {
        lock.lock()
        stored.append(url)
        lock.unlock()
    }

    var urls: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}

struct RollupBudgetTests {
    @Test func rollupUpdatesAreCappedAndTheFinalTreeIsComplete() async throws {
        let dir = try TempDir()
        for number in 0..<12 { try dir.file("root/d\(number)/file", bytes: 1024) }
        var builder = FileIndexBuilder(policy: dir.policy, threads: 1)
        builder.rollupMaxDepth = 0
        builder.rollupMinBytes = 0
        builder.rollupLevels = 1
        builder.rollupUpdateLimit = 2
        let root = dir.url.appendingPathComponent("root")
        let box = UpdateBox()
        builder.onRollup = { box.append($0.url) }
        let built = try await builder.build(roots: [root])
        #expect(box.urls.count <= 3)
        #expect(box.urls.contains { $0.path == root.path })
        #expect(built.trees.first?.children.count == 12)
    }
}
