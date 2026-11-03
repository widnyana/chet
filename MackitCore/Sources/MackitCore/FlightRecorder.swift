import Darwin
import Foundation
import Synchronization

/// Process-wide flight recorder. Keeps the last scan and clean events in a fixed, pre-rendered
/// ring (the crash handler reads its tail without locks or allocation) and mirrors events to a
/// capped, rotated JSONL file so deaths the handler cannot catch (SIGKILL) stay diagnosable
/// within the flush policy.
public final class FlightRecorder: Sendable {
    /// Fixed record size and ring depth. Slots are pre-rendered JSON lines; nothing on the
    /// record path allocates.
    public static let slotBytes = 256
    public static let ringSlots = 512
    public static let flushEvents = 16
    public static let flushInterval: TimeInterval = 5
    public static let maxFileBytes: Int64 = 1_000_000
    public static let rotatedKept = 4

    /// The instance installed for the running app; the crash handler reads its ring tail.
    /// Set once at launch (MackitApp), read from a signal handler.
    public nonisolated(unsafe) static var shared: FlightRecorder?

    /// Per-run identifier; distinguishes runs in the log and in crash reports.
    public let sessionID = UUID().uuidString
    private let directory: URL
    private let ringSlotsLimit: Int
    private let tailEventsLimit: Int
    private let flushEvery: Int
    private let flushAfter: TimeInterval
    private let maxBytes: Int64
    private let kept: Int
    private let slotSize: Int

    /// Injectable clock (seconds since 1970), so tests can move time.
    public let now: @Sendable () -> TimeInterval

    /// Mirrored tail for the crash path: the writer fills the inactive buffer completely,
    /// then flips. The handler loads the active index/length with acquire ordering and copies
    /// without retry — the buffer it sees is always a complete, stable copy.
    private final class TailMirror: @unchecked Sendable {
        let a: UnsafeMutableRawPointer
        let b: UnsafeMutableRawPointer
        let capacity: Int
        let lenA = Atomic<Int>(0)
        let lenB = Atomic<Int>(0)
        let active = Atomic<Int>(0)

        init(capacity: Int) {
            self.capacity = capacity
            a = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: 1)
            b = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: 1)
        }
    }

    /// Mutable recorder state; guarded by the mutex. The tail mirror is the lock-free exception.
    private final class State: @unchecked Sendable {
        var slotData: [UInt8]
        var slotLen: [Int]
        var writeIndex = 0
        var filled = 0
        var pending: [UInt8]
        var pendingCount = 0
        var pendingEvents = 0
        var lastFlush: TimeInterval
        var fd: Int32 = -1
        var fileSize: Int64 = 0
        var available = true

        init(slotBytes: Int, ringSlots: Int, pendingSlots: Int) {
            slotData = [UInt8](repeating: 0, count: ringSlots * slotBytes)
            slotLen = [Int](repeating: 0, count: ringSlots)
            pending = [UInt8](repeating: 0, count: pendingSlots * slotBytes)
            lastFlush = 0
        }
    }

    private let state: Mutex<State>
    private let mirror: TailMirror

    public init(
        directory: URL,
        ringSlots: Int = FlightRecorder.ringSlots,
        tailEvents: Int = 32,
        flushEvery: Int = FlightRecorder.flushEvents,
        flushAfter: TimeInterval = FlightRecorder.flushInterval,
        maxFileBytes: Int64 = FlightRecorder.maxFileBytes,
        rotatedKept: Int = FlightRecorder.rotatedKept,
        now: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSince1970 }
    ) {
        self.directory = directory
        self.ringSlotsLimit = max(ringSlots, tailEvents)
        self.tailEventsLimit = tailEvents
        self.flushEvery = flushEvery
        self.flushAfter = flushAfter
        self.maxBytes = maxFileBytes
        self.kept = rotatedKept
        self.slotSize = Self.slotBytes
        self.now = now
        let initial = now()
        self.state = Mutex(State(slotBytes: slotSize, ringSlots: ringSlotsLimit, pendingSlots: min(max(flushEvery, 1), 64) + 2))
        self.mirror = TailMirror(capacity: tailEvents * slotSize)
        state.withLock { $0.lastFlush = initial }
        openMirrorFile()
    }

    public var isAvailable: Bool { state.withLock { $0.available } }

    /// Appends one pre-rendered JSON line to the ring and the pending mirror buffer.
    /// No allocation: fixed-size copies into preallocated storage only.
    public func record(line bytes: [UInt8]) {
        state.withLock { s in
            guard s.available else { return }
            let n = min(bytes.count, slotSize - 1)
            let offset = s.writeIndex * slotSize
            for i in 0..<n { s.slotData[offset + i] = bytes[i] }
            s.slotData[offset + n] = 0x0A
            s.slotLen[s.writeIndex] = n + 1
            s.writeIndex = (s.writeIndex + 1) % ringSlotsLimit
            s.filled = min(s.filled + 1, ringSlotsLimit)
            rebuildTail(s, lastCount: min(tailEventsLimit, s.filled))
            s.pendingEvents += 1
            var i = bytes.startIndex
            for _ in 0..<n {
                appendPendingByte(s, bytes[i])
                i = bytes.index(after: i)
            }
            appendPendingByte(s, 0x0A)
            let t = now()
            if s.pendingEvents >= flushEvery || t - s.lastFlush >= flushAfter { flushLocked(s) }
        }
    }

    /// Renders one event to a JSON line (clamped so it stays valid JSON inside a slot) and records it.
    public func record(step: String, _ summary: String) {
        record(line: Self.render(time: now(), session: sessionID, step: step, summary: summary))
    }

    /// The newest events, for tests and diagnostics (allocates; never called from the handler).
    public func tailData() -> Data {
        var buffer = [UInt8](repeating: 0, count: tailEventsLimit * slotSize)
        let n = buffer.withUnsafeMutableBytes { ptr in
            tail(into: ptr.baseAddress!, capacity: ptr.count)
        }
        return Data(buffer[0..<n])
    }

    /// Lock-free, allocation-free tail copy for the crash handler: reads the stable mirrored
    /// buffer the writer finished before its last flip. Never retries, never takes the mutex.
    public func tail(into buffer: UnsafeMutableRawPointer, capacity: Int) -> Int {
        let index = mirror.active.load(ordering: .acquiring)
        var n = 0
        if index == 0 {
            n = min(mirror.lenA.load(ordering: .acquiring), mirror.capacity, capacity)
            if n > 0 { _ = memcpy(buffer, mirror.a, n) }
        } else {
            n = min(mirror.lenB.load(ordering: .acquiring), mirror.capacity, capacity)
            if n > 0 { _ = memcpy(buffer, mirror.b, n) }
        }
        return n
    }

    public func flushForTesting() {
        state.withLock { s in
            guard s.available else { return }
            flushLocked(s)
        }
    }

    /// Splits JSONL bytes into complete lines; a trailing line without `\n` (a torn write from a
    /// crash mid-flush) is discarded.
    public static func validLines(from data: Data) -> [Data] {
        var lines: [Data] = []
        var start = data.startIndex
        var i = data.startIndex
        while i < data.endIndex {
            if data[i] == 0x0A {
                if i > start { lines.append(Data(data[start..<i])) }
                start = data.index(after: i)
            }
            i = data.index(after: i)
        }
        return lines
    }

    /// Minimal JSON line rendering; the summary is clamped so the line fits one slot and the
    /// JSON stays parseable (an over-long summary is cut at a whole-character boundary).
    static func render(time: TimeInterval, session: String, step: String, summary: String) -> [UInt8] {
        func escaped(_ s: String) -> String {
            var out = ""
            for ch in s {
                switch ch {
                case "\"": out += "\\\""
                case "\\": out += "\\\\"
                case "\n", "\r", "\t": out += " "
                default:
                    if ch.unicodeScalars.allSatisfy({ $0.value < 0x20 }) { out += " " } else { out.append(ch) }
                }
            }
            return out
        }
        var line =
            "{\"time\":\"\(String(format: "%.0f", time))\",\"session\":\"\(escaped(session))\",\"step\":\"\(escaped(step))\",\"summary\":\""
        let suffix = "\"}"
        let budget = Self.slotBytes - 1 - line.utf8.count - suffix.utf8.count
        var body = escaped(summary)
        while body.utf8.count > max(budget, 1) { body.removeLast() }
        line += body
        return Array((line + suffix).utf8)
    }

    // MARK: - internals (all called with state locked)

    private func appendPendingByte(_ s: State, _ byte: UInt8) {
        guard s.pendingCount < s.pending.count else { return }
        s.pending[s.pendingCount] = byte
        s.pendingCount += 1
    }

    private func rebuildTail(_ s: State, lastCount: Int) {
        let inactive = 1 - mirror.active.load(ordering: .relaxed)
        let target = inactive == 0 ? mirror.a : mirror.b
        var offset = 0
        // Newest first: walk backwards from writeIndex - 1.
        for k in 0..<lastCount {
            let index = (s.writeIndex - 1 - k + ringSlotsLimit * 2) % ringSlotsLimit
            let len = s.slotLen[index]
            _ = memcpy(target + offset, UnsafeRawPointer(s.slotData) + index * slotSize, len)
            offset += len
        }
        if inactive == 0 {
            mirror.lenA.store(offset, ordering: .releasing)
        } else {
            mirror.lenB.store(offset, ordering: .releasing)
        }
        mirror.active.store(inactive, ordering: .releasing)
    }

    private func openMirrorFile() {
        state.withLock { s in
            if (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) == nil {
                s.available = false
                return
            }
            let current = directory.appendingPathComponent("flight.current").path
            let fd = open(current, O_WRONLY | O_CREAT | O_APPEND, 0o644)
            guard fd >= 0 else { s.available = false; return }
            if flock(fd, LOCK_EX | LOCK_NB) != 0 {
                _ = close(fd)
                let fallback = directory.appendingPathComponent("flight-\(getpid()).log").path
                let ffd = open(fallback, O_WRONLY | O_CREAT | O_APPEND, 0o644)
                guard ffd >= 0 else { s.available = false; return }
                s.fd = ffd
                s.fileSize = 0
            } else {
                s.fd = fd
                s.fileSize = Int64(lseek(fd, 0, SEEK_END))
            }
        }
    }

    private func flushLocked(_ s: State) {
        guard s.pendingCount > 0, s.fd >= 0 else { return }
        let written = s.pending.withUnsafeBytes { ptr -> Int in
            write(s.fd, ptr.baseAddress!, s.pendingCount)
        }
        guard written > 0 else {
            // Disk full or otherwise unwritable: drop the batch, disable further recording.
            s.available = false
            s.pendingCount = 0
            return
        }
        s.fileSize += Int64(written)
        s.pendingCount = 0
        s.pendingEvents = 0
        s.lastFlush = now()
        if s.fileSize >= maxBytes { rotateLocked(s) }
    }

    private func rotateLocked(_ s: State) {
        // Runtime rotation only — never from the crash path. Reopens a fresh flight.current.
        _ = close(s.fd)
        s.fd = -1
        let dir = self.directory
        let base: (String) -> URL = { dir.appendingPathComponent($0) }
        if kept > 0 {
            try? FileManager.default.removeItem(at: base("flight.\(kept).jsonl"))
            for i in stride(from: kept - 1, through: 1, by: -1) {
                let from = base("flight.\(i).jsonl").path
                let to = base("flight.\(i + 1).jsonl").path
                if FileManager.default.fileExists(atPath: from) { _ = rename(from, to) }
            }
            _ = rename(base("flight.current").path, base("flight.1.jsonl").path)
        } else {
            try? FileManager.default.removeItem(at: base("flight.current"))
        }
        let fd = open(base("flight.current").path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        guard fd >= 0 else { s.available = false; return }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 { s.available = false; _ = close(fd); return }
        s.fd = fd
        s.fileSize = 0
    }
}
