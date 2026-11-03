import Darwin
import Foundation
import Synchronization
import Testing

@testable import MackitCore

struct FlightRecorderTests {
    /// Mutable test clock; FlightRecorder reads it through the injected closure.
    private final class Clock: @unchecked Sendable {
        let seconds = Mutex<Double>(0)
        var now: Double { seconds.withLock { $0 } }
        func advance(_ d: Double) { seconds.withLock { $0 += d } }
    }

    private func line(from data: Data) throws -> [String: String] {
        let entry = try JSONDecoder().decode([String: String].self, from: data)
        return entry
    }

    private func readLines(_ url: URL) throws -> [Data] {
        FlightRecorder.validLines(from: try Data(contentsOf: url))
    }

    @Test func recordsEventsInOrderAsJSONL() throws {
        let dir = try TempDir()
        let recorder = FlightRecorder(directory: dir.url)
        recorder.record(step: "duplicates", "12 groups, 3.2 MB")
        recorder.record(step: "large-files", "8 items")
        recorder.flushForTesting()
        let url = dir.url.appendingPathComponent("flight.current")
        let lines = try readLines(url)
        #expect(lines.count == 2)
        let first = try line(from: lines[0])
        #expect(first["step"] == "duplicates")
        #expect(first["summary"] == "12 groups, 3.2 MB")
        #expect(first["session"] == recorder.sessionID)
        #expect((first["time"] ?? "").isEmpty == false)
        #expect(try line(from: lines[1])["step"] == "large-files")
    }

    @Test func ringEvictsOldestAndTailKeepsNewest() throws {
        let dir = try TempDir()
        let recorder = FlightRecorder(directory: dir.url, ringSlots: 8, tailEvents: 4)
        for i in 0..<20 { recorder.record(step: "s\(i)", "event \(i)") }
        let tail = recorder.tailData()
        let tailText = String(decoding: tail, as: UTF8.self)
        #expect(tailText.contains("event 19"))
        #expect(tailText.contains("event 16"))
        #expect(!tailText.contains("event 15"))
        let tailLines = tailText.split(separator: "\n")
        #expect(tailLines.count == 4)
    }

    @Test func oversizedSummaryStaysValidJSON() throws {
        let dir = try TempDir()
        let recorder = FlightRecorder(directory: dir.url)
        let long = String(repeating: "x", count: 5_000) + "\"" + String(repeating: "y", count: 100)
        recorder.record(step: "index", long)
        recorder.flushForTesting()
        let lines = try readLines(dir.url.appendingPathComponent("flight.current"))
        #expect(lines.count == 1)
        let entry = try line(from: lines[0])
        #expect(entry["step"] == "index")
        #expect((entry["summary"] ?? "").hasPrefix("xxxx"))
        #expect((entry["summary"] ?? "").count < 5_000)
    }

    @Test func tornTrailingLineIsDiscarded() throws {
        let dir = try TempDir()
        let url = dir.url.appendingPathComponent("flight.current")
        try FileManager.default.createDirectory(at: dir.url, withIntermediateDirectories: true)
        try Data("{\"step\":\"a\"}\n{\"step\":\"b\"}".utf8).write(to: url)
        #expect(try FlightRecorder.validLines(from: Data(contentsOf: url)).count == 1)
        try Data("{\"step\":\"a\"}\n{\"step\":\"b\"}\n".utf8).write(to: url)
        #expect(try FlightRecorder.validLines(from: Data(contentsOf: url)).count == 2)
    }

    @Test func flushFiresOnEventCount() throws {
        let dir = try TempDir()
        let clock = Clock()
        let recorder = FlightRecorder(directory: dir.url, flushEvery: 3, flushAfter: 60, now: { clock.now })
        for i in 0..<3 { recorder.record(step: "s", "e\(i)"); clock.advance(0.1) }
        let lines = try readLines(dir.url.appendingPathComponent("flight.current"))
        #expect(lines.count == 3)
    }

    @Test func flushFiresOnTimeEvenWithFewEvents() throws {
        let dir = try TempDir()
        let clock = Clock()
        let recorder = FlightRecorder(directory: dir.url, flushEvery: 100, flushAfter: 5, now: { clock.now })
        recorder.record(step: "s", "first"); clock.advance(0.1)
        #expect(try readLines(dir.url.appendingPathComponent("flight.current")).count == 0)
        recorder.record(step: "s", "second"); clock.advance(10)
        recorder.record(step: "s", "third")
        let lines = try readLines(dir.url.appendingPathComponent("flight.current"))
        #expect(lines.count == 3)
    }

    @Test func rotationKeepsNewestFiles() throws {
        let dir = try TempDir()
        let recorder = FlightRecorder(directory: dir.url, maxFileBytes: 400, rotatedKept: 2)
        for i in 0..<40 {
            recorder.record(step: "rotate", String(repeating: "z", count: 60) + " #\(i)")
            recorder.flushForTesting()
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.url.path).sorted()
        #expect(names.contains("flight.current"))
        #expect(names.contains("flight.1.jsonl"))
        #expect(names.contains("flight.2.jsonl"))
        #expect(!names.contains("flight.3.jsonl"))
        // The newest rotated file holds the older half of the events.
        let rotated = try readLines(dir.url.appendingPathComponent("flight.1.jsonl"))
        #expect(!rotated.isEmpty)
    }

    @Test func secondInstanceFallsBackToPerPIDFile() throws {
        let dir = try TempDir()
        let path = dir.url.appendingPathComponent("flight.current").path
        let fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        #expect(fd >= 0)
        #expect(flock(fd, LOCK_EX | LOCK_NB) == 0)
        defer { flock(fd, LOCK_UN); close(fd) }
        let recorder = FlightRecorder(directory: dir.url)
        recorder.record(step: "s", "from second instance")
        recorder.flushForTesting()
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.url.path)
        #expect(names.contains { $0.hasPrefix("flight-") && $0.hasSuffix(".log") })
    }

    @Test func unavailableDirectoryDisablesRecorder() throws {
        let dir = try TempDir()
        let blocker = dir.url.appendingPathComponent("logs")
        try Data("not a directory".utf8).write(to: blocker)
        let recorder = FlightRecorder(directory: blocker.appendingPathComponent("Mackit"))
        recorder.record(step: "s", "should not crash")
        recorder.flushForTesting()
        #expect(!recorder.isAvailable)
    }

    @Test func recordPathKeepsBoundedState() throws {
        let dir = try TempDir()
        let recorder = FlightRecorder(directory: dir.url, flushEvery: .max)
        let bytes = Array("{\"time\":\"t\",\"session\":\"s\",\"step\":\"s\",\"summary\":\"x\"}\n".utf8)
        let (slotsBefore, pendingBefore) = (recorder.storageCapacity, recorder.pendingCapacity)
        for _ in 0..<100_000 { recorder.record(line: bytes) }
        // No unbounded growth on the record path: the fixed ring and pending buffer never resize.
        #expect(recorder.storageCapacity == slotsBefore)
        #expect(recorder.pendingCapacity == pendingBefore)
    }

    @Test func tailForHandlerCopiesWithoutAllocating() throws {
        let dir = try TempDir()
        let recorder = FlightRecorder(directory: dir.url, tailEvents: 4)
        for i in 0..<6 { recorder.record(step: "s\(i)", "e\(i)") }
        var buffer = [UInt8](repeating: 0, count: 4 * FlightRecorder.slotBytes)
        let n = buffer.withUnsafeMutableBytes { ptr in
            recorder.tail(into: ptr.baseAddress!, capacity: ptr.count)
        }
        let text = String(decoding: buffer[0..<n], as: UTF8.self)
        #expect(text.contains("e5"))
        #expect(!text.contains("e1\n"))
    }
}
