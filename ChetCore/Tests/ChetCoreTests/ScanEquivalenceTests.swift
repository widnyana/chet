import Foundation
import Synchronization
import Testing

@testable import ChetCore

@Suite(.serialized)
struct ScanEquivalenceTests {
    private struct Outcome: Equatable {
        let step: ScanStep
        let done: Int
        let itemCount: Int
        let totalBytes: Int64
    }

    private func outcomes(_ events: [ScanEvent]) -> [Outcome] {
        events.compactMap { event in
            switch event {
            case .stepActivity(let step, let done, let total, _):
                Outcome(step: step, done: done, itemCount: 0, totalBytes: Int64(total))
            case .folderTrees(let trees, _):
                Outcome(
                    step: .index, done: 0, itemCount: trees.count,
                    totalBytes: trees.reduce(0) { $0 + $1.size })
            case .finished(let step):
                Outcome(step: step, done: 0, itemCount: 0, totalBytes: 0)
            default:
                nil
            }
        }
    }

    private func fixture() throws -> TempDir {
        let dir = try TempDir()
        try dir.file("alpha/one.bin", bytes: 4_000)
        try dir.file("alpha/two.bin", bytes: 6_000)
        try dir.file("beta/three.bin", bytes: 5_000)
        return dir
    }

    @Test func loggingDoesNotChangeScanOutcomes() async throws {
        let fixture = try fixture()
        let logDirectory = try TempDir()
        let writer = ActivityLog(
            url: logDirectory.url.appendingPathComponent(ActivityLogLimits.baseName))
        defer {
            writer.close()
            VerboseLog.install(nil)
        }

        let sessionA = ScanSession(
            home: fixture.url, largeFileMinSize: 1_000, enabledSteps: [.index])
        let eventsA = Mutex<[ScanEvent]>([])
        VerboseLog.install(writer)
        await sessionA.run { event in
            eventsA.withLock { $0.append(event) }
            VerboseLog.event(.info, .scan, .scanEvent, .count(.files, 1))
        }
        writer.flush()

        let sessionB = ScanSession(
            home: fixture.url, largeFileMinSize: 1_000, enabledSteps: [.index])
        let eventsB = Mutex<[ScanEvent]>([])
        VerboseLog.install(nil)
        await sessionB.run { event in
            eventsB.withLock { $0.append(event) }
        }

        #expect(outcomes(eventsA.withLock { $0 }) == outcomes(eventsB.withLock { $0 }))
        #expect(!eventsA.withLock { $0 }.isEmpty)
        let text = try String(
            contentsOf: logDirectory.url.appendingPathComponent(ActivityLogLimits.baseName),
            encoding: .utf8)
        #expect(text.split(separator: "\n").count >= 1)
    }
}
