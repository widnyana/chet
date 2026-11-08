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

    /// The one log directory every Mackit writer (AuditLog, FlightRecorder, CrashHandler,
    /// LogMaintenance) uses; derive paths from this, never from a literal.
    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Mackit")
    }

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
        /// False when another instance holds flight.current and this one writes its PID file.
        var ownsCurrent = true

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
        self.now = now
        let initial = now()
        self.state = Mutex(
            State(slotBytes: Self.slotBytes, ringSlots: ringSlotsLimit, pendingSlots: min(max(flushEvery, 1), 64) + 2))
        self.mirror = TailMirror(capacity: tailEvents * Self.slotBytes)
        state.withLock { $0.lastFlush = initial }
        openMirrorFile()
    }

    public var isAvailable: Bool { state.withLock { $0.available } }

    /// Fixed capacities, exposed for the bounded-state test (no unbounded growth on the
    /// record path). Not part of the public API contract.
    var storageCapacity: Int { state.withLock { $0.slotData.count } }
    var pendingCapacity: Int { state.withLock { $0.pending.count } }

    /// Appends one pre-rendered JSON line to the ring and the pending mirror buffer.
    /// No allocation: fixed-size copies into preallocated storage only.
    public func record(line bytes: [UInt8]) {
        state.withLock { s in
            guard s.available else { return }
            let n = min(bytes.count, Self.slotBytes - 1)
            let offset = s.writeIndex * Self.slotBytes
            for i in 0..<n { s.slotData[offset + i] = bytes[i] }
            s.slotData[offset + n] = 0x0A
            s.slotLen[s.writeIndex] = n + 1
            s.writeIndex = (s.writeIndex + 1) % ringSlotsLimit
            s.filled = min(s.filled + 1, ringSlotsLimit)
            rebuildTail(s, lastCount: min(tailEventsLimit, s.filled))
            s.pendingEvents += 1
            for byte in bytes[0..<n] { appendPendingByte(s, byte) }
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
        var buffer = [UInt8](repeating: 0, count: tailEventsLimit * Self.slotBytes)
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

    /// Flushes any pending events to the mirror file now. Call at scan end/cancel so the
    /// last events never wait for the next record (the time-based trigger only fires then).
    public func flushNow() {
        state.withLock { s in
            guard s.available else { return }
            flushLocked(s)
        }
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
        // Single pass over characters, budget in bytes; equivalent to repeated removeLast
        // (longest character prefix whose UTF-8 length fits) without the O(n²) recount.
        if body.utf8.count > max(budget, 1) {
            var cut = body.startIndex
            var bytes = 0
            for i in body.indices {
                let w = body[i].utf8.count
                guard bytes + w <= max(budget, 1) else { break }
                bytes += w
                cut = body.index(after: i)
            }
            body = String(body[..<cut])
        }
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
        s.slotData.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
            for k in 0..<lastCount {
                let index = (s.writeIndex - 1 - k + ringSlotsLimit * 2) % ringSlotsLimit
                let len = s.slotLen[index]
                _ = memcpy(target + offset, src.baseAddress! + index * Self.slotBytes, len)
                offset += len
            }
        }
        if inactive == 0 {
            mirror.lenA.store(offset, ordering: .releasing)
        } else {
            mirror.lenB.store(offset, ordering: .releasing)
        }
        mirror.active.store(inactive, ordering: .releasing)
    }

    /// Opens `path` for append and takes its flock; -1 (with the fd closed) on any failure.
    private func openLocked(_ path: String) -> Int32 {
        let fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        guard fd >= 0 else { return -1 }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            _ = close(fd)
            return -1
        }
        return fd
    }

    private func openMirrorFile() {
        state.withLock { s in
            if (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) == nil {
                s.available = false
                return
            }
            let fd = openLocked(directory.appendingPathComponent("flight.current").path)
            if fd >= 0 {
                s.fd = fd
                s.fileSize = Int64(lseek(fd, 0, SEEK_END))
                return
            }
            // Lock held elsewhere: the per-PID fallback file needs no flock (PID-exclusive name).
            let ffd = open(
                directory.appendingPathComponent("flight-\(getpid()).log").path,
                O_WRONLY | O_CREAT | O_APPEND, 0o644)
            guard ffd >= 0 else {
                s.available = false
                return
            }
            s.fd = ffd
            s.fileSize = 0
        }
    }

    private func flushLocked(_ s: State) {
        guard s.pendingCount > 0, s.fd >= 0 else { return }
        var writtenTotal = 0
        while writtenTotal < s.pendingCount {
            let n = s.pending.withUnsafeBytes { ptr -> Int in
                write(s.fd, ptr.baseAddress! + writtenTotal, s.pendingCount - writtenTotal)
            }
            if n > 0 {
                writtenTotal += n
            } else if errno == EINTR {
                continue
            } else {
                // Disk full or otherwise unwritable: drop the batch, disable further recording.
                s.available = false
                s.pendingCount = 0
                return
            }
        }
        s.fileSize += Int64(writtenTotal)
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
        if !s.ownsCurrent {
            // The other instance owns flight.current; renaming it would corrupt its file.
            // This instance's PID file just stops growing: disable further recording.
            s.available = false
            return
        }
        if kept > 0 {
            try? FileManager.default.removeItem(at: base("flight.\(kept).jsonl"))
            for i in stride(from: kept - 1, through: 1, by: -1) {
                let from = base("flight.\(i).jsonl").path
                let to = base("flight.\(i + 1).jsonl").path
                // Missing source just fails the rename; no existence pre-check (TOCTOU).
                _ = rename(from, to)
            }
            _ = rename(base("flight.current").path, base("flight.1.jsonl").path)
        } else {
            try? FileManager.default.removeItem(at: base("flight.current"))
        }
        let fd = openLocked(base("flight.current").path)
        guard fd >= 0 else {
            s.available = false
            return
        }
        s.fd = fd
        s.fileSize = 0
    }
}

// MARK: - ScanEvent summaries (pure and unit-testable; ScanModel forwards, see KTD8)

extension FlightRecorder {
    /// Pure mapping from a scan event to a (step, summary) pair. Every event maps to
    /// something; the shape is deliberately step-level (counts, bytes, top paths) — never
    /// raw payloads.
    public static func summary(for event: ScanEvent) -> (step: String, summary: String) {
        switch event {
        case .started(let step): return (step.rawValue, "started")
        case .finished(let step): return (step.rawValue, "finished")
        case .done: return ("scan", "complete")
        case .rules(let result):
            return (
                result.category,
                "\(result.items.count) items, \(result.totalBytes) bytes\(result.needsFullDiskAccess ? ", FDA missing" : "")"
            )
        case .taggedCaches(let items): return ("tagged-caches", itemsSummary(items))
        case .largeFiles(let items): return ("large-files", itemsSummary(items))
        case .leftovers(let items): return ("leftovers", itemsSummary(items))
        case .duplicates(let groups):
            let bytes = groups.reduce(Int64(0)) { $0 + $1.reclaimableBytes }
            return ("duplicates", "\(groups.count) groups, \(bytes) bytes reclaimable")
        case .photos(let result):
            return ("photos", "\(result.clusters.count) clusters, \(result.blurry.count) blurry")
        case .videos(let clusters):
            let bytes = clusters.reduce(Int64(0)) { $0 + $1.reclaimableBytes }
            return ("videos", "\(clusters.count) clusters, \(bytes) bytes reclaimable")
        case .snapshots(let snapshots):
            return ("snapshots", "\(snapshots.count) local snapshots")
        case .folderTrees(let trees):
            return ("index", "\(trees.count) root trees measured")
        }
    }

    /// "N items, X bytes; top: name (bytes), ..." — at most 5 paths, largest first.
    static func itemsSummary(_ items: [ScanItem]) -> String {
        let bytes = items.reduce(Int64(0)) { $0 + $1.reclaimableBytes }
        let top = items.sorted { $0.reclaimableBytes > $1.reclaimableBytes }.prefix(5)
            .map { "\($0.url.lastPathComponent) (\($0.reclaimableBytes))" }
        return "\(items.count) items, \(bytes) bytes" + (top.isEmpty ? "" : "; top: " + top.joined(separator: ", "))
    }

    /// Records a scan event as one step summary.
    public func record(_ event: ScanEvent) {
        let s = Self.summary(for: event)
        record(step: s.step, s.summary)
    }
}
