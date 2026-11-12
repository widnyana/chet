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

    private static let buildCategoryIDs: Set<String> = ["dev-garbage", "terraform-build-dirs"]

    private func mergedCategories(_ events: [ScanEvent]) -> [String: [ScanItem]] {
        var categories: [String: [ScanItem]] = [:]
        var builds: [ScanItem] = []
        for event in events {
            switch event {
            case .rules(let result):
                if Self.buildCategoryIDs.contains(result.category) {
                    builds += result.items
                    if let tagged = categories["tagged-caches"] {
                        categories["tagged-caches"] = TaggedCachePrecedence.keep(
                            tagged, builds: builds)
                    }
                }
                categories[result.category, default: []] += result.items
            case .taggedCaches(let items):
                categories["tagged-caches", default: []] += TaggedCachePrecedence.keep(
                    items, builds: builds)
            default:
                break
            }
        }
        return categories.filter { !$0.value.isEmpty }
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
        #expect(tagged.first?.sizeBasis == .reclaimable)
    }

    @Test func ruleItemsCarryTheAllocatedBasis() async throws {
        let dir = try TempDir()
        try dir.file("Library/Caches/a/x", bytes: 5_000_000)
        try dir.file("Library/Caches/b/y", bytes: 3_000_000)
        let events = await collect(ScanSession(home: dir.url, enabledSteps: [.rules]))
        let caches = events.compactMap { event -> [ScanItem]? in
            if case .rules(let result) = event, result.category == "caches" { result.items } else { nil }
        }.flatMap { $0 }
        #expect(caches.count == 2)
        #expect(caches.allSatisfy { $0.sizeBasis == .allocated })
        #expect(caches.reduce(0) { $0 + $1.reclaimableBytes } > 7_900_000)
    }

    @Test func taggedVirtualEnvironmentStaysInBuildCategory() async throws {
        let dir = try TempDir()
        let venv = "Development/proj/.venv"
        try dir.file("\(venv)/pyvenv.cfg", bytes: 100)
        try dir.file("\(venv)/lib/python3.14/site-packages/x.py", bytes: 2_000_000, fill: 5)
        try Data("Signature: 8a477f597d28d172789f06886806bc55\n".utf8).write(
            to: dir.url.appendingPathComponent("\(venv)/CACHEDIR.TAG"))
        let events = await collect(ScanSession(home: dir.url, enabledSteps: [.rules, .index]))
        let merged = mergedCategories(events)
        #expect(merged["dev-garbage"]?.map(\.url.lastPathComponent) == [".venv"])
        #expect(merged["dev-garbage"]?.map(\.kind) == ["Python venv"])
        #expect(merged["tagged-caches"] == nil)
    }

    @Test func taggedSwiftBuildStaysInBuildCategory() async throws {
        let dir = try TempDir()
        let build = "Development/proj/.build"
        try dir.file("\(build)/debug/blob", bytes: 2_000_000, fill: 6)
        try Data("Signature: 8a477f597d28d172789f06886806bc55\n".utf8).write(
            to: dir.url.appendingPathComponent("\(build)/CACHEDIR.TAG"))
        let events = await collect(ScanSession(home: dir.url, enabledSteps: [.rules, .index]))
        let merged = mergedCategories(events)
        #expect(merged["dev-garbage"]?.map(\.url.lastPathComponent) == [".build"])
        #expect(merged["dev-garbage"]?.map(\.kind) == ["Swift build"])
        #expect(merged["tagged-caches"] == nil)
    }

    @Test func unrelatedTaggedDirectoryStaysInTaggedCaches() async throws {
        let dir = try TempDir()
        let cache = "Development/proj/cachetree"
        try dir.file("\(cache)/blob", bytes: 2_000_000, fill: 7)
        try Data("Signature: 8a477f597d28d172789f06886806bc55\n".utf8).write(
            to: dir.url.appendingPathComponent("\(cache)/CACHEDIR.TAG"))
        let events = await collect(ScanSession(home: dir.url, enabledSteps: [.rules, .index]))
        let merged = mergedCategories(events)
        #expect(merged["dev-garbage"] == nil)
        #expect(merged["tagged-caches"]?.map(\.url.lastPathComponent) == ["cachetree"])
    }

    @Test func taggedCacheAheadOfBuildCategoryIsRemoved() throws {
        let dir = try TempDir()
        let buildURL = dir.url.appendingPathComponent("Development/proj/target")
        try dir.file("Development/proj/target/debug/blob", bytes: 1_000)
        let stamp = try #require(FileStamp.read(buildURL))
        let tagged = ScanItem(
            url: buildURL, categoryID: "tagged-caches", risk: .safe, mode: .permanent,
            reclaimableBytes: 1_000, stamp: stamp)
        let build = ScanItem(
            url: buildURL, categoryID: "dev-garbage", risk: .review, mode: .trash,
            reclaimableBytes: 1_000, stamp: stamp)
        let result = CategoryResult(
            ruleID: "dev-garbage", category: "dev-garbage", items: [build],
            needsFullDiskAccess: false)
        let merged = mergedCategories([.taggedCaches([tagged]), .rules(result)])
        #expect(merged["tagged-caches"] == nil)
        #expect(merged["dev-garbage"]?.map(\.url) == [buildURL])
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

    @Test func mergedRecordKeepsTheConservativeVerdictOnce() throws {
        let dir = try TempDir()
        let url = try dir.file("Library/Caches/com.example/blob", bytes: 128)
        let stamp = try #require(FileStamp.read(url))
        let safe = ScanItem(
            url: url, categoryID: "caches", risk: .safe, mode: .permanent,
            reclaimableBytes: 4_096, stamp: stamp)
        let review = ScanItem(
            url: url, categoryID: "leftovers", risk: .review, mode: .trash,
            reclaimableBytes: 4_096, stamp: stamp)
        var ledger = ScanLedger()
        ledger.record(safe)
        ledger.selectIfSafe(url)
        #expect(ledger.selected == [url])

        ledger.record(review)
        ledger.selectIfSafe(url)

        #expect(ledger.itemsByURL.count == 1)
        #expect(ledger.itemsByURL[url]?.risk == .review)
        #expect(ledger.itemsByURL[url]?.mode == .trash)
        #expect(ledger.selected.isEmpty)
        #expect(ledger.totalBytes == 4_096)
    }

    @Test func repeatingTheSameVerdictLeavesTheRecordUnchanged() throws {
        let dir = try TempDir()
        let url = try dir.file("Library/Caches/com.example/blob", bytes: 128)
        let stamp = try #require(FileStamp.read(url))
        let item = ScanItem(
            url: url, categoryID: "caches", risk: .safe, mode: .permanent,
            reclaimableBytes: 4_096, stamp: stamp)
        var ledger = ScanLedger()
        ledger.record(item)
        ledger.selectIfSafe(url)
        let first = ledger.itemsByURL[url]

        ledger.record(item)
        ledger.selectIfSafe(url)

        #expect(ledger.itemsByURL[url] == first)
        #expect(ledger.selected == [url])
        #expect(ledger.totalBytes == 4_096)
    }
}
