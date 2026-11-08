import Foundation
import Testing

@testable import MackitCore

/// The flight-recorder instrumentation: pure event summaries, and the clean call site that
/// appends a batch summary beside the AuditLog's per-file rows.
struct RecorderInstrumentationTests {
    private func summaryText(_ event: ScanEvent) -> String {
        let s = FlightRecorder.summary(for: event)
        return "\(s.step): \(s.summary)"
    }

    private func item(_ path: String, bytes: Int64) throws -> ScanItem {
        let dir = try TempDir()
        let url = try dir.file(path, bytes: Int(bytes))
        let stamp = try #require(FileStamp.read(url))
        return ScanItem(
            url: url, categoryID: "test", risk: .safe, mode: .permanent, reclaimableBytes: bytes, stamp: stamp)
    }

    @Test func startedAndFinishedMapToTheirStep() {
        #expect(summaryText(.started(.index)) == "index: started")
        #expect(summaryText(.finished(.duplicates)) == "duplicates: finished")
        #expect(summaryText(.done) == "scan: complete")
    }

    @Test func itemArraysCarryCountsBytesAndTopPaths() throws {
        let a = try item("big/a", bytes: 500)
        let b = try item("small/b", bytes: 100)
        let items = [a, b]
        let text = summaryText(.largeFiles(items))
        #expect(text.contains("large-files"))
        #expect(text.contains("2 items, 600 bytes"))
        #expect(text.contains("top: a (500), b (100)"))
    }

    @Test func duplicatesAndMediaSummariesCarryTotals() {
        let text = summaryText(.photos(PhotoScanResult(clusters: [], blurry: [])))
        #expect(text == "photos: 0 clusters, 0 blurry")
        let videos = summaryText(.videos([]))
        #expect(videos == "videos: 0 clusters, 0 bytes reclaimable")
    }

    @Test func remainingEventCasesMapToTheirSteps() throws {
        let dir = try TempDir()
        let a = try dir.file("x", bytes: 10)
        let stamp = try #require(FileStamp.read(a))
        let items = [
            ScanItem(
                url: a, categoryID: "test", risk: .safe, mode: .permanent, reclaimableBytes: 10, stamp: stamp)
        ]
        #expect(summaryText(.taggedCaches(items)).hasPrefix("tagged-caches: 1 items, 10 bytes"))
        #expect(summaryText(.leftovers(items)).hasPrefix("leftovers: 1 items, 10 bytes"))
        #expect(summaryText(.folderTrees([])) == "index: 0 root trees measured")
        #expect(summaryText(.snapshots([])) == "snapshots: 0 local snapshots")
        let ruleResult = CategoryResult(ruleID: "caches", category: "caches", items: items, needsFullDiskAccess: true)
        let rulesText = summaryText(.rules(ruleResult))
        #expect(rulesText.contains("caches"))
        #expect(rulesText.contains("FDA missing"))
    }

    @Test func cleanRunWritesBatchSummaryToFlightLogAndRowsToCleanLog() throws {
        let dir = try TempDir()
        let recorder = FlightRecorder(directory: dir.url)
        let cleanLog = dir.url.appendingPathComponent("clean.log")
        var cleaner = Cleaner(policy: dir.policy, log: AuditLog(url: cleanLog), recorder: recorder)
        cleaner.isRunning = { _ in false }
        let a = try dir.file("cache/a", bytes: 100)
        let stampA = try #require(FileStamp.read(a))
        let items = [
            ScanItem(
                url: a, categoryID: "test", risk: .safe, mode: .permanent, reclaimableBytes: stampA.size,
                stamp: stampA)
        ]
        _ = cleaner.clean(items)
        recorder.flushForTesting()
        let flightText = String(
            decoding: try Data(contentsOf: dir.url.appendingPathComponent("flight.current")), as: UTF8.self)
        #expect(flightText.contains("clean"))
        #expect(flightText.contains("1 checked, 100 bytes freed"))
        // Per-file rows stay in clean.log only.
        let cleanLines = try String(contentsOf: cleanLog, encoding: .utf8).split(separator: "\n")
        #expect(cleanLines.count == 1)
    }

    @Test func startedWithoutFinishedShowsStepInFlight() throws {
        let dir = try TempDir()
        let recorder = FlightRecorder(directory: dir.url)
        recorder.record(.started(.index))
        recorder.record(step: "index", "progress: 12000 files, 44 GB, in /Users/me/Library/Caches")
        // No .finished(.index) was recorded: the log names the step in flight and its folder.
        recorder.flushForTesting()
        let text = String(
            decoding: try Data(contentsOf: dir.url.appendingPathComponent("flight.current")), as: UTF8.self)
        #expect(text.contains("\"step\":\"index\""))
        #expect(text.contains("\"summary\":\"started\""))
        #expect(text.contains("in /Users/me/Library/Caches"))
        #expect(!text.contains("\"summary\":\"finished\""))
    }
}
