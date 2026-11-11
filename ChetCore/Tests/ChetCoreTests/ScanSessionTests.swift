import Darwin
import Foundation
import Testing

@testable import ChetCore

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

    @Test func rootMeasuredArrivesPerRootBeforeFolderTrees() async throws {
        let dir = try TempDir()
        for name in ["Documents", "Movies", "Downloads"] {
            try dir.file("\(name)/big.bin", bytes: 2_000_000, fill: 7)
        }
        var events: [ScanEvent] = []
        for await event in ScanSession(home: dir.url, largeFileMinSize: 2_500_000).events() {
            events.append(event)
            if case .done = event { break }
        }
        let roots = events.compactMap { event -> FolderNode? in
            if case .rootMeasured(let node) = event { node } else { nil }
        }
        #expect(Set(roots.map { $0.url.lastPathComponent }) == ["Documents", "Movies", "Downloads"])
        #expect(roots.allSatisfy { $0.size >= 2_000_000 })
        // Every rootMeasured precedes the final folderTrees event.
        let treeIndex = events.firstIndex { if case .folderTrees = $0 { true } else { false } } ?? events.count
        let rootIndices = events.indices.filter { if case .rootMeasured = events[$0] { true } else { false } }
        #expect(rootIndices.allSatisfy { $0 < treeIndex })
        // Progress snapshots carry the running root and totals.
        let snapshots = events.compactMap { event -> ProgressSnapshot? in
            if case .progress(let snapshot) = event { snapshot } else { nil }
        }
        #expect(
            snapshots.isEmpty || snapshots.allSatisfy { $0.rootsTotal == 3 && $0.runningRootURL != nil })
    }

    @Test func everyPhaseReportsStepActivity() async throws {
        let dir = try TempDir()
        try dir.file("Documents/a/copy", bytes: 2_000_000, fill: 9)
        try dir.file("Documents/b/copy", bytes: 2_000_000, fill: 9)
        var events: [ScanEvent] = []
        for await event in ScanSession(home: dir.url, largeFileMinSize: 2_500_000).events() {
            events.append(event)
            if case .done = event { break }
        }
        let activities = events.compactMap { event -> (ScanStep, Int, Int, String)? in
            if case .stepActivity(let step, let done, let total, let label) = event {
                return (step, done, total, label)
            }
            return nil
        }
        // Every phase announces itself.
        #expect(Set(activities.map(\.0)) == Set(ScanStep.allCases))
        #expect(activities.allSatisfy { !$0.3.isEmpty })
        // The rules step counts every catalog rule exactly once.
        let rules = activities.filter { $0.0 == .rules && $0.2 > 0 }
        #expect(rules.last?.1 == Rule.catalog.count)
        #expect(rules.last?.2 == Rule.catalog.count)
        #expect(rules.map(\.1) == rules.map(\.1).sorted())
    }

    @Test func taggedCargoTargetBecomesOneCacheItem() async throws {
        let dir = try TempDir()
        try dir.file("Development/proj/target/debug/blob", bytes: 2_000_000, fill: 3)
        try Data("Signature: 8a477f597d28d172789f06886806bc55\n".utf8).write(
            to: dir.url.appendingPathComponent("Development/proj/target/CACHEDIR.TAG"))
        var events: [ScanEvent] = []
        for await event in ScanSession(home: dir.url, largeFileMinSize: 2_500_000).events() {
            events.append(event)
            if case .done = event { break }
        }
        let tagged = events.compactMap { event -> [ScanItem]? in
            if case .taggedCaches(let items) = event { items } else { nil }
        }.flatMap { $0 }
        #expect(tagged.count == 1)
        #expect(tagged.first?.url.lastPathComponent == "target")
        #expect(tagged.first?.categoryID == "tagged-caches")
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
            case .folderTrees(let nodes, _): trees = nodes.count
            default: break
            }
        }
        #expect(duplicateCount == 1)
        #expect(largeNames == ["huge.bin"])
        #expect(taggedNames == ["target"])
        #expect(cacheNames == ["com.example.tool"])
        #expect(trees == 3)
    }

    @Test func disabledStepsFinishWithoutRunning() async throws {
        let dir = try TempDir()
        try dir.file("Documents/a/copy", bytes: 2_000_000, fill: 9)
        var enabled = Set(ScanStep.allCases)
        enabled.remove(.photos)
        enabled.remove(.videos)
        var events: [ScanEvent] = []
        for await event in ScanSession(home: dir.url, enabledSteps: enabled).events() {
            events.append(event)
            if case .done = event { break }
        }
        let started = events.compactMap { event -> ScanStep? in
            if case .started(let step) = event { step } else { nil }
        }
        let finished = events.compactMap { event -> ScanStep? in
            if case .finished(let step) = event { step } else { nil }
        }
        #expect(!started.contains(.photos))
        #expect(!started.contains(.videos))
        #expect(finished.contains(.photos))
        #expect(finished.contains(.videos))
        #expect(Set(started).contains(.rules))
    }

    @Test func extraRuleProducesItsCategory() async throws {
        let dir = try TempDir()
        try dir.file("Downloads/old/a.bin", bytes: 1_000_000)
        let rule = UserRule(path: dir.url.appendingPathComponent("Downloads/old").path).rule
        var seen: [String: Int] = [:]
        for await event in ScanSession(home: dir.url, extraRules: [rule]).events() {
            if case .rules(let result) = event { seen[result.category, default: 0] += result.items.count }
            if case .done = event { break }
        }
        #expect(seen["user-rules"] == 1)
    }

    @Test func userRootsKeepOnlyDirectories() throws {
        let dir = try TempDir()
        try dir.file("Documents/x", bytes: 1)
        try dir.file("loose.txt", bytes: 1)
        try FileManager.default.createDirectory(
            at: dir.url.appendingPathComponent("Archive.app"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: dir.url.appendingPathComponent("linked"),
            withDestinationURL: dir.url.appendingPathComponent("Documents"))
        #expect(Set(ScanSession.userRoots(dir.url).map(\.lastPathComponent)) == ["Documents"])
    }

    @Test func skippedIndexErrnosNameVanishedPathErrors() {
        #expect(ScanSession.skippedIndexErrnos == [ENOTDIR, ENOENT, ELOOP, EACCES])
    }

    @Test func indexErrorsOnNonDirectoriesAreSkipped() throws {
        let dir = try TempDir()
        let loose = try dir.text("loose.txt", "x")
        let vanished = dir.url.appendingPathComponent("vanished", isDirectory: true)
        let loop = dir.url.appendingPathComponent("loop")
        try FileManager.default.createSymbolicLink(at: loop, withDestinationURL: loop)
        for errno in [ENOTDIR, ENOENT, ELOOP, EACCES] {
            #expect(!ScanSession.indexErrorIsReportable(WalkError(url: loose, errno: errno)))
        }
        #expect(!ScanSession.indexErrorIsReportable(WalkError(url: vanished, errno: ENOENT)))
        #expect(!ScanSession.indexErrorIsReportable(WalkError(url: loop, errno: ELOOP)))
    }

    @Test func indexErrorsOnRegularFileRootsAreNotEmitted() async throws {
        let dir = try TempDir()
        let loose = try dir.text("loose.txt", "not a folder")
        for await event in ScanSession(
            home: dir.url, enabledSteps: [.index], scanScope: ScanScope(roots: [loose.path])
        ).events() {
            if case .readErrors(let errors) = event {
                #expect(errors.isEmpty)
                return
            }
        }
        Issue.record("the index step emitted no readErrors event")
    }

    @Test func unreadableDirectoryRootIsEmittedAsAReadError() async throws {
        let dir = try TempDir()
        let locked = dir.url.appendingPathComponent("Locked", isDirectory: true)
        try dir.text("Locked/inside.txt", "x")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: locked.path)
        }
        #expect(ScanSession.indexErrorIsReportable(WalkError(url: locked, errno: EACCES)))
        var reported: [WalkError] = []
        for await event in ScanSession(
            home: dir.url, enabledSteps: [.index], scanScope: ScanScope(roots: [locked.path])
        ).events() {
            if case .readErrors(let errors) = event {
                reported = errors
                break
            }
        }
        let lockedCanonical = ScanScope.canonicalPath(locked.path)
        #expect(
            reported.contains {
                ScanScope.canonicalPath($0.url.path) == lockedCanonical && $0.errno == EACCES
            })
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
