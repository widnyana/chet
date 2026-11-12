import Darwin
import Foundation
import Synchronization
import os

public enum LogLevel: String, Sendable, Encodable {
    case debug
    case info
    case warn
    case error
}

public enum LogCategory: String, Sendable, Encodable {
    case launch
    case scan
    case index
    case rules
    case clean
    case storage
    case uninstall
    case tweaks
    case settings
    case process
    case ui
}

public enum LogMessage: String, Sendable, Encodable {
    case launchStarted = "launch.started"
    case crashReportRotated = "launch.crashReportRotated"
    case launchTerminated = "launch.terminated"
    case scanStarted = "scan.started"
    case scanEvent = "scan.event"
    case scanCategory = "scan.category"
    case rulesProgress = "rules.progress"
    case rulesResult = "rules.result"
    case indexProgress = "index.progress"
    case indexRollup = "index.rollup"
    case indexUnreadable = "index.unreadable"
    case indexFinished = "index.finished"
    case cleanRefused = "clean.refused"
    case cleanRefusedBatch = "clean.refusedBatch"
    case cleanCancelled = "clean.cancelled"
    case cleanStarted = "clean.started"
    case cleanFinished = "clean.finished"
    case cleanSummary = "clean.summary"
    case storageSnapshotCreated = "storage.snapshotCreated"
    case storageSnapshotDeleted = "storage.snapshotDeleted"
    case storageTrashMove = "storage.trashMove"
    case storageEmptyTrash = "storage.emptyTrash"
    case uninstallFinished = "uninstall.finished"
    case tweakRead = "tweak.read"
    case tweakApply = "tweak.apply"
    case tweakRevert = "tweak.revert"
    case tweakPreview = "tweak.preview"
    case settingsChanged = "settings.changed"
    case processRun = "process.run"
    case uiViewAppeared = "ui.viewAppeared"
    case uiSheetPresented = "ui.sheetPresented"
    case uiNavigationChanged = "ui.navigationChanged"
}

public enum LogFieldKey: String, Sendable, Encodable {
    case count
    case bytes
    case durationMS
    case status
    case errno
    case rotationsKept
    case lifetime
    case argCount
    case done
    case total
    case files
    case items
    case components
    case readings
    case entries
    case trees
    case readErrors
    case rootsDone
    case rootsTotal
    case depth
    case selected
    case freed
    case removed
    case trashed
    case skipped
    case failed
    case dryRunCount
    case errnoSamples
    case gated
    case threads
    case excludedPaths
    case extraRules
    case enabledSteps
    case largeFileThreshold
    case duplicateSize
    case oldAgeDays
    case folder
    case item
    case executable
    case snapshot
    case relativePath
    case bundleID
    case tweakID
    case allowOutsideHome
    case dryRun
    case needsFullDiskAccess
    case sawCrash
    case recorded
    case allowed
    case ok
    case step
    case category
    case mode
    case outcome
    case refusal
    case sizeBasis
    case settingsKey
    case reply
    case verification
    case view
    case sheet
}

public enum LogFieldValue: Sendable, Equatable {
    case count(Int)
    case bytes(Int64)
    case durationMS(Int)
    case status(Int32)
    case basename(Basename)
    case path(RelativePath)
    case redacted(RedactionTag)
}

public struct LogField: Sendable, Equatable, Encodable {
    public let key: LogFieldKey
    public let value: LogFieldValue

    public init(key: LogFieldKey, value: LogFieldValue) {
        self.key = key
        self.value = value
    }

    public static func count(_ key: LogFieldKey, _ value: Int) -> LogField {
        LogField(key: key, value: .count(value))
    }

    public static func bytes(_ key: LogFieldKey, _ value: Int64) -> LogField {
        LogField(key: key, value: .bytes(value))
    }

    public static func durationMS(_ key: LogFieldKey, _ value: Int) -> LogField {
        LogField(key: key, value: .durationMS(value))
    }

    public static func status(_ key: LogFieldKey, _ value: Int32) -> LogField {
        LogField(key: key, value: .status(value))
    }

    public init(_ key: LogFieldKey, _ value: LogFieldValue) {
        self.init(key: key, value: value)
    }

    public static func flag(_ key: LogFieldKey, _ value: Bool) -> LogField {
        LogField(key: key, value: .status(value ? 1 : 0))
    }

    public static func code(_ key: LogFieldKey, _ value: LogCode) -> LogField {
        LogField(key: key, value: .status(value.rawValue))
    }

    public static func basename(_ key: LogFieldKey, _ value: Basename?) -> LogField? {
        value.map { LogField(key: key, value: .basename($0)) }
    }

    public static func path(_ key: LogFieldKey, _ value: RelativePath?) -> LogField? {
        value.map { LogField(key: key, value: .path($0)) }
    }

    public static func redacted(_ key: LogFieldKey, _ value: RedactionTag) -> LogField {
        LogField(key: key, value: .redacted(value))
    }

    private enum CodingKeys: String, CodingKey {
        case key
        case value
    }

    private enum ValueCodingKeys: String, CodingKey {
        case count
        case bytes
        case durationMS
        case status
        case basename
        case path
        case redacted
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        var nested = container.nestedContainer(keyedBy: ValueCodingKeys.self, forKey: .value)
        switch value {
        case .count(let payload): try nested.encode(payload, forKey: .count)
        case .bytes(let payload): try nested.encode(payload, forKey: .bytes)
        case .durationMS(let payload): try nested.encode(payload, forKey: .durationMS)
        case .status(let payload): try nested.encode(payload, forKey: .status)
        case .basename(let payload): try nested.encode(payload.value, forKey: .basename)
        case .path(let payload): try nested.encode(payload.value, forKey: .path)
        case .redacted(let payload): try nested.encode(payload, forKey: .redacted)
        }
    }
}

public enum LogCode: Int32, Sendable {
    case stepScan = 1
    case stepIndex = 2
    case stepRules = 3
    case stepDuplicates = 4
    case stepLargeFiles = 5
    case stepLeftovers = 6
    case stepPhotos = 7
    case stepVideos = 8
    case stepSnapshots = 9
    case stepTaggedCaches = 10

    case categoryCaches = 100
    case categoryLogs = 101
    case categoryDownloads = 102
    case categoryTrash = 103
    case categorySnapshots = 104
    case categoryLargeFiles = 105
    case categoryDuplicates = 106
    case categoryLeftovers = 107
    case categoryPhotos = 108
    case categoryVideos = 109
    case categoryApps = 110
    case categoryHomebrew = 111
    case categoryBrowser = 112
    case categoryDevGarbage = 113
    case categoryXcode = 114
    case categoryOther = 115

    case modePermanent = 200
    case modeTrash = 201

    case outcomeMoved = 300
    case outcomeWouldMove = 301
    case outcomeFailed = 302
    case outcomeOk = 303
    case outcomeRefused = 304
    case outcomeCancelled = 305
    case refusal = 306

    case sizeBasisAllocated = 400

    case settingsKeyScanThreads = 500
    case settingsKeyScanScope = 501
    case settingsKeyExcludedPaths = 502
    case settingsKeyUserRules = 503
    case settingsKeyDuplicateMinSize = 504
    case settingsKeyLargeFileMinAge = 505
    case settingsKeyIncludeTemp = 506
    case settingsKeyScanOutsideHome = 507
    case settingsKeyTweakPreview = 508
    case settingsKeyLargeFileMinSize = 509

    case replyOk = 600
    case replyRefused = 601
    case replyFailed = 602

    case verificationOk = 700
    case verificationMismatch = 701
    case verificationSkipped = 702

    case viewHome = 800
    case viewApps = 801
    case viewHomebrew = 802
    case viewStorage = 803
    case viewTweaks = 804
    case viewSettings = 805
    case viewSnapshots = 806
    case viewMise = 807
    case viewGo = 808
    case viewAbout = 809

    case sheetClean = 900
    case sheetConfirm = 901
    case sheetTrash = 902
    case sheetUninstall = 903
    case sheetInstaller = 904
    case sheetScanScope = 905
}

public enum RedactionTag: String, Sendable, Encodable {
    case bundleID
    case tweakID
    case environment
    case argv
    case payload
    case userName
    case absolutePath
}

public struct Basename: Sendable, Equatable {
    public let value: String

    public init?(_ value: String) {
        guard value.utf8.count <= ActivityLogLimits.maxBasenameBytes, !value.contains("/") else { return nil }
        self.value = value
    }

    public init?(path: String) {
        guard let last = path.split(separator: "/").last else { return nil }
        self.init(String(last))
    }
}

public struct RelativePath: Sendable, Equatable {
    public let value: String

    public init?(_ value: String) {
        guard !value.isEmpty, !value.hasPrefix("/") else { return nil }
        guard !value.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == ".." })
        else { return nil }
        self.value = value
    }
}

public struct LogRecord: Sendable, Encodable {
    public let time: String
    public let session: String
    public let level: LogLevel
    public let category: LogCategory
    public let message: LogMessage
    public let fields: [LogField]
}

public enum ActivityLogLimits {
    public static let baseName = "application-debug.log"
    public static let rotatedName = "application-debug.1.log"
    public static let prunePrefix = "application-debug"
    public static let pruneSuffix = ".log"
    public static let maxFileBytes: Int64 = 1_048_576
    public static let keptFiles = 2
    public static let flushEvents = 16
    public static let flushInterval: TimeInterval = 5
    public static let maxBasenameBytes = 128
    public static let maxRecordBytes = 2_048
}

enum ActivityLogFailure: Error {
    case directoryUnavailable(errno: Int32)
    case openFailed(errno: Int32)
    case lockUnavailable
    case reopenFailed(errno: Int32)
    case writeFailed(errno: Int32)
    case shortWrite(expected: Int, wrote: Int)
    case rotateFailed(errno: Int32)
    case renderFailed
}

public final class ActivityLog: Sendable {
    public let sessionID: String
    public let url: URL
    public let rotationsKept: Int

    private let clock: @Sendable () -> Date
    private let maxBytes: Int64
    private let state: Mutex<WriterState>

    private struct WriterState: Sendable {
        enum Role: Sendable {
            case owner
            case nonOwner
        }

        var fd: Int32 = -1
        var pending: [UInt8] = []
        var liveBytes: Int64 = 0
        var recordCount = 0
        var lastFlush: Date
        var isAvailable = true
        var role: Role = .owner
        var inode: UInt64 = 0
        var droppedRecords = 0

        init(lastFlush: Date) {
            self.lastFlush = lastFlush
        }
    }

    private static let logger = Logger(subsystem: "id.web.widnyana.chet", category: "devlog")

    public init(
        url: URL = FlightRecorder.defaultDirectory.appendingPathComponent(ActivityLogLimits.baseName),
        clock: @escaping @Sendable () -> Date = { Date() },
        maxBytes: Int64 = ActivityLogLimits.maxFileBytes,
        kept: Int = ActivityLogLimits.keptFiles
    ) {
        self.sessionID = UUID().uuidString
        self.url = url
        self.clock = clock
        self.maxBytes = maxBytes
        let directory = url.deletingLastPathComponent()
        let directoryReady =
            (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true))
            != nil
        self.rotationsKept =
            directoryReady
            ? LogMaintenance.pruneLogs(
                in: directory, prefix: ActivityLogLimits.prunePrefix,
                suffix: ActivityLogLimits.pruneSuffix, kept: kept)
            : 0
        self.state = Mutex(WriterState(lastFlush: clock()))
        guard directoryReady else {
            fail(.directoryUnavailable(errno: errno))
            return
        }
        do {
            try state.withLock { s in
                try openOwned(&s)
                if s.liveBytes + 1 > maxBytes {
                    if let failure = rotate(&s) { throw failure }
                }
            }
        } catch let failure as ActivityLogFailure {
            guard case .lockUnavailable = failure else {
                fail(failure)
                return
            }
            do {
                try state.withLock { s in try openShared(&s) }
            } catch let reopen as ActivityLogFailure {
                fail(reopen)
            } catch {
                fail(.reopenFailed(errno: errno))
            }
        } catch {
            fail(.openFailed(errno: errno))
        }
    }

    public var isAvailable: Bool {
        state.withLock { $0.isAvailable }
    }

    var droppedRecords: Int {
        state.withLock { $0.droppedRecords }
    }

    public func append(
        _ level: LogLevel, _ category: LogCategory, _ message: LogMessage, _ fields: [LogField] = []
    ) {
        state.withLock { s in
            guard s.isAvailable, s.fd >= 0 else { return }
            let record = LogRecord(
                time: clock().formatted(Date.ISO8601FormatStyle()), session: sessionID, level: level,
                category: category, message: message, fields: fields)
            guard let line = try? Self.render(record) else {
                s.droppedRecords += 1
                return
            }
            guard line.count <= ActivityLogLimits.maxRecordBytes else {
                s.droppedRecords += 1
                return
            }
            if s.role == .owner, s.liveBytes + Int64(line.count) > maxBytes {
                if let failure = rotate(&s) {
                    degrade(&s, failure)
                    return
                }
            }
            s.pending.append(contentsOf: line)
            s.recordCount += 1
            let elapsed = clock().timeIntervalSince(s.lastFlush)
            if s.recordCount >= ActivityLogLimits.flushEvents || elapsed >= ActivityLogLimits.flushInterval
                || level != .debug
            {
                flushLocked(&s)
            }
        }
    }

    public func flush() {
        state.withLock { s in
            guard s.isAvailable else { return }
            flushLocked(&s)
        }
    }

    public func close() {
        state.withLock { s in
            guard s.fd >= 0 else { return }
            flushLocked(&s)
            _ = Darwin.close(s.fd)
            s.fd = -1
            s.pending.removeAll(keepingCapacity: true)
        }
    }

    private static func render(_ record: LogRecord) throws -> [UInt8] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do {
            var data = try encoder.encode(record)
            data.append(0x0A)
            return Array(data)
        } catch {
            throw ActivityLogFailure.renderFailed
        }
    }

    private func openOwned(_ s: inout WriterState) throws {
        let fd = open(url.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        guard fd >= 0 else { throw ActivityLogFailure.openFailed(errno: errno) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            _ = Darwin.close(fd)
            throw ActivityLogFailure.lockUnavailable
        }
        s.fd = fd
        s.role = .owner
        try seed(&s)
    }

    private func openShared(_ s: inout WriterState) throws {
        let fd = open(url.path, O_WRONLY | O_APPEND)
        guard fd >= 0 else { throw ActivityLogFailure.reopenFailed(errno: errno) }
        s.fd = fd
        s.role = .nonOwner
        try seed(&s)
    }

    private func seed(_ s: inout WriterState) throws {
        var info = stat()
        guard fstat(s.fd, &info) == 0 else { throw ActivityLogFailure.openFailed(errno: errno) }
        s.liveBytes = Int64(info.st_size)
        s.inode = UInt64(info.st_ino)
    }

    private func rotate(_ s: inout WriterState) -> ActivityLogFailure? {
        guard s.role == .owner else { return nil }
        flushLocked(&s)
        guard s.isAvailable else { return nil }
        let previous = s.fd
        let rotated = url.deletingLastPathComponent().appendingPathComponent(ActivityLogLimits.rotatedName)
        guard rename(url.path, rotated.path) == 0 else { return .rotateFailed(errno: errno) }
        let fd = open(url.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        guard fd >= 0 else {
            let code = errno
            if previous >= 0 { _ = Darwin.close(previous) }
            s.fd = -1
            return .rotateFailed(errno: code)
        }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            _ = Darwin.close(fd)
            if previous >= 0 { _ = Darwin.close(previous) }
            s.fd = -1
            return .rotateFailed(errno: code)
        }
        if previous >= 0 { _ = Darwin.close(previous) }
        s.fd = fd
        var info = stat()
        guard fstat(fd, &info) == 0 else {
            let code = errno
            _ = Darwin.close(fd)
            s.fd = -1
            return .rotateFailed(errno: code)
        }
        s.liveBytes = Int64(info.st_size)
        s.inode = UInt64(info.st_ino)
        return nil
    }

    private func reopenIfRotated(_ s: inout WriterState) -> ActivityLogFailure? {
        var opened = stat()
        guard fstat(s.fd, &opened) == 0 else { return .reopenFailed(errno: errno) }
        var live = stat()
        guard stat(url.path, &live) == 0 else { return .reopenFailed(errno: errno) }
        guard UInt64(opened.st_ino) != UInt64(live.st_ino) else { return nil }
        _ = Darwin.close(s.fd)
        s.fd = -1
        let fd = open(url.path, O_WRONLY | O_APPEND)
        guard fd >= 0 else { return .reopenFailed(errno: errno) }
        s.fd = fd
        s.liveBytes = Int64(live.st_size)
        s.inode = UInt64(live.st_ino)
        return nil
    }

    private func flushLocked(_ s: inout WriterState) {
        guard s.isAvailable, s.fd >= 0 else { return }
        if s.role == .nonOwner {
            if let failure = reopenIfRotated(&s) {
                degrade(&s, failure)
                return
            }
        }
        guard !s.pending.isEmpty else {
            s.recordCount = 0
            s.lastFlush = clock()
            return
        }
        let expected = s.pending.count
        let wrote = s.pending.withUnsafeBytes { buffer in
            write(s.fd, buffer.baseAddress, expected)
        }
        if wrote < 0 {
            degrade(&s, .writeFailed(errno: errno))
            return
        }
        guard wrote == expected else {
            degrade(&s, .shortWrite(expected: expected, wrote: wrote))
            return
        }
        s.liveBytes += Int64(wrote)
        s.pending.removeAll(keepingCapacity: true)
        s.recordCount = 0
        s.lastFlush = clock()
    }

    private func degrade(_ s: inout WriterState, _ failure: ActivityLogFailure) {
        let wasAvailable = s.isAvailable
        s.isAvailable = false
        s.pending.removeAll(keepingCapacity: true)
        if s.fd >= 0 {
            _ = Darwin.close(s.fd)
            s.fd = -1
        }
        if wasAvailable {
            Self.logger.notice("activity log unavailable: \(String(describing: failure), privacy: .public)")
        }
    }

    private func fail(_ failure: ActivityLogFailure) {
        state.withLock { s in degrade(&s, failure) }
    }
}
