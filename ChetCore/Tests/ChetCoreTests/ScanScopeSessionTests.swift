import Foundation
import Testing

@testable import ChetCore

/// Serialized: the IO policy is process-wide.
@Suite(.serialized)
struct ScanScopeSessionTests {
    private func collect(_ session: ScanSession) async -> [ScanEvent] {
        var events: [ScanEvent] = []
        for await event in session.events() {
            events.append(event)
            if case .done = event { break }
        }
        return events
    }

    private func started(_ step: ScanStep, in events: [ScanEvent]) -> Bool {
        events.contains { if case .started(step) = $0 { true } else { false } }
    }

    @Test func categoryScopeScansOnlyThatCategory() async throws {
        let dir = try TempDir()
        try dir.file("Library/Caches/dev.chet.fixture/payload.bin", bytes: 2_000_000)
        try dir.file("Documents/holiday.bin", bytes: 2_000_000)
        let events = await collect(
            ScanSession(home: dir.url, scanScope: ScanScope(categories: ["caches"])))

        let categories = Set(
            events.compactMap { event -> String? in
                if case .rules(let result) = event { result.category } else { nil }
            })
        #expect(categories == ["caches"])
        #expect(!started(.index, in: events))
        #expect(!started(.largeFiles, in: events))
    }

    @Test func rootScopeMeasuresOnlyThoseRoots() async throws {
        let dir = try TempDir()
        try dir.file("Documents/a/keep.bin", bytes: 1_000)
        try dir.file("Movies/b/skip.bin", bytes: 1_000)
        let documents = dir.url.appendingPathComponent("Documents").path
        let events = await collect(
            ScanSession(home: dir.url, scanScope: ScanScope(roots: [documents])))

        let trees = events.compactMap { event -> [FolderNode]? in
            if case .folderTrees(let nodes, _) = event { nodes } else { nil }
        }
        #expect(trees.last?.map(\.url.lastPathComponent) == ["Documents"])
        #expect(started(.index, in: events))
    }

    @Test func aRootOutsideHomeNeedsTheSettingsOptIn() throws {
        let dir = try TempDir()
        let outside = try TempDir()
        let scope = ScanScope(roots: [dir.url.path, outside.url.path])
        let denied = ScanSession.scanRoots(home: dir.url, scope: scope, allowOutsideHome: false)
        #expect(denied.count == 1)
        #expect(denied.first.map { ScanScope.canonicalPath($0.path) } == ScanScope.canonicalPath(dir.url.path))
        let allowed = ScanSession.scanRoots(home: dir.url, scope: scope, allowOutsideHome: true)
        #expect(allowed.count == 2)
    }

    @Test func defaultScopeKeepsEveryStep() async throws {
        let dir = try TempDir()
        try dir.file("Documents/a/one.bin", bytes: 1_000)
        let events = await collect(ScanSession(home: dir.url))
        #expect(started(.index, in: events))
        #expect(started(.largeFiles, in: events))
    }
}
