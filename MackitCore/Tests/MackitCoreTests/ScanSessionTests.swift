import Darwin
import Foundation
import Testing

@testable import MackitCore

/// Serialized: the IO policy is process-wide.
@Suite(.serialized)
struct ScanSessionTests {
    private func collect(_ session: ScanSession) async -> [ScanEvent] {
        var events: [ScanEvent] = []
        for await event in session.events() { events.append(event) }
        return events
    }

    @Test func userRootsSkipLibraryAndHiddenFolders() throws {
        let dir = try TempDir()
        for name in ["Documents/x", "Library/x", ".cache/x", "Movies/x"] { try dir.file(name, bytes: 1) }
        #expect(Set(ScanSession.userRoots(dir.url).map(\.lastPathComponent)) == ["Documents", "Movies"])
    }

    @Test func stepsRunInOrderAndFindEachKind() async throws {
        let dir = try TempDir()
        try dir.file("Documents/a/copy", bytes: 2_000_000, fill: 9)
        try dir.file("Documents/b/copy", bytes: 2_000_000, fill: 9)
        try dir.file("Movies/huge.bin", bytes: 3_000_000, fill: 2)
        try dir.file("Library/Caches/com.example.tool/blob", bytes: 1_000)
        try dir.file("Development/proj/target/blob", bytes: 2_000_000, fill: 3)
        try Data("Signature: 8a477f597d28d172789f06886806bc55\n".utf8).write(
            to: dir.url.appendingPathComponent("Development/proj/target/CACHEDIR.TAG"))
        let events = await collect(ScanSession(home: dir.url, largeFileMinSize: 2_500_000))

        let started = events.compactMap { event -> ScanStep? in
            if case .started(let step) = event { step } else { nil }
        }
        #expect(started == ScanStep.allCases)
        guard case .done = events.last else {
            Issue.record("scan did not end with .done")
            return
        }
        var duplicateCount = -1
        var largeNames: [String] = []
        var taggedNames: [String] = []
        var cacheNames: [String] = []
        var trees = 0
        for event in events {
            switch event {
            case .duplicates(let groups): duplicateCount = groups.count
            case .largeFiles(let items): largeNames = items.map(\.url.lastPathComponent)
            case .taggedCaches(let items): taggedNames = items.map(\.url.lastPathComponent)
            case .rules(let result) where result.category == "caches":
                cacheNames += result.items.map(\.url.lastPathComponent)
            case .folderTrees(let nodes): trees = nodes.count
            default: break
            }
        }
        #expect(duplicateCount == 1)
        #expect(largeNames == ["huge.bin"])
        #expect(taggedNames == ["target"])
        #expect(cacheNames == ["com.example.tool"])
        #expect(trees == 3)
    }

    @Test func leavingTheStreamStopsTheScanAndRestoresIOPolicy() async throws {
        let dir = try TempDir()
        for i in 0..<200 { try dir.file("Documents/f\(i)", bytes: 10) }
        let before = getiopolicy_np(IOPOL_TYPE_DISK, IOPOL_SCOPE_PROCESS)
        var seen: [ScanEvent] = []
        for await event in ScanSession(home: dir.url).events() {
            seen.append(event)
            if case .finished(.rules) = event { break }
        }
        #expect(!seen.contains { if case .done = $0 { true } else { false } })
        var restored = false
        for _ in 0..<60 {
            if getiopolicy_np(IOPOL_TYPE_DISK, IOPOL_SCOPE_PROCESS) == before {
                restored = true
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(restored)
    }
}
