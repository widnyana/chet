import AppKit
import Foundation

public enum SkipReason: String, Sendable {
    case missing, changed, policy, appRunning, localState
}

public enum CleanOutcome: Sendable, Equatable {
    case removed(Int64)
    case trashed(Int64)
    case skipped(SkipReason)
    case failed(String)

    var logValue: String {
        switch self {
        case .removed: "removed"
        case .trashed: "trashed"
        case .skipped(let reason): "skipped:\(reason.rawValue)"
        case .failed(let message): "failed:\(message)"
        }
    }
}

public struct CleanResult: Sendable {
    public let item: ScanItem
    public let outcome: CleanOutcome
    /// True when this row is a dry-run simulation, not a performed action.
    public let dryRun: Bool
}

/// One live sample of a clean pass. The UI uses it for the progress indicator and
/// the verbose box; the audit log still owns the durable per-item record.
public struct CleanProgress: Sendable, Equatable {
    public let processed: Int
    public let total: Int
    public let processedBytes: Int64
    public let totalBytes: Int64
    public let freedBytes: Int64
    public let skipped: Int
    public let failed: Int
    public let currentPath: String
    public let currentBytes: Int64
    public let currentMode: DeleteMode
    /// True when the selected item is a folder. The cleaner counts selected
    /// items, not every file inside a folder.
    public let currentIsDirectory: Bool
    /// True for the sample emitted after the last item. It separates "preparing"
    /// from "finishing snapshots" when the item list is empty.
    public let isFinal: Bool

    public init(
        processed: Int, total: Int, processedBytes: Int64, totalBytes: Int64, freedBytes: Int64,
        skipped: Int, failed: Int, currentPath: String, currentBytes: Int64, currentMode: DeleteMode,
        currentIsDirectory: Bool = false, isFinal: Bool = false
    ) {
        self.processed = processed
        self.total = total
        self.processedBytes = processedBytes
        self.totalBytes = totalBytes
        self.freedBytes = freedBytes
        self.skipped = skipped
        self.failed = failed
        self.currentPath = currentPath
        self.currentBytes = currentBytes
        self.currentMode = currentMode
        self.currentIsDirectory = currentIsDirectory
        self.isFinal = isFinal
    }

    public var itemFraction: Double {
        total > 0 ? Double(processed) / Double(total) : 0
    }

    public var byteFraction: Double {
        totalBytes > 0 ? Double(processedBytes) / Double(totalBytes) : 0
    }

    public var currentFileNumber: Int {
        total > 0 ? min(processed + 1, total) : 0
    }

    public static func preparing(total: Int, totalBytes: Int64) -> CleanProgress {
        CleanProgress(
            processed: 0, total: total, processedBytes: 0, totalBytes: totalBytes, freedBytes: 0,
            skipped: 0, failed: 0, currentPath: "", currentBytes: 0, currentMode: .permanent)
    }
}

public struct CleanReport: Sendable {
    public var results: [CleanResult] = []
    /// True when every row was simulated by the dry-run gate; UI and logs must never
    /// present a dry-run report as a real deletion.
    public var dryRun = false

    public var freedBytes: Int64 {
        results.reduce(0) { total, result in
            switch result.outcome {
            case .removed(let bytes), .trashed(let bytes): total + bytes
            case .skipped, .failed: total
            }
        }
    }
}

/// Removes selected items. Each item is checked again right before deletion: it must still be the
/// same file (inode, size, mtime), still pass the safety policy, and its owning app must not run.
public struct Cleaner: Sendable {
    public let policy: SafetyPolicy
    public let log: AuditLog
    /// When set, receives one batch summary per clean run (per-file rows go only to `log`).
    public let recorder: FlightRecorder?
    /// Dry-run gate: when true, every guard still runs and success is reported, but no file
    /// is removed or trashed. Required, not defaulted: every composition root must decide
    /// explicitly, so an unwired cleaner cannot silently mutate.
    public let dryRun: Bool
    /// Bundle ID of the app that owns an item, if any.
    public var owner: @Sendable (ScanItem) -> String? = { _ in nil }
    public var isRunning: @Sendable (String) -> Bool = { id in
        !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
    }
    public var trash: @Sendable (URL) throws -> Void = { url in
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    public init(
        policy: SafetyPolicy, log: AuditLog = AuditLog(), recorder: FlightRecorder? = nil, dryRun: Bool
    ) {
        self.policy = policy
        self.log = log
        self.recorder = recorder
        self.dryRun = dryRun
    }

    public func clean(
        _ items: [ScanItem],
        progress: (@Sendable (CleanProgress) -> Void)? = nil
    ) -> CleanReport {
        var report = CleanReport()
        report.dryRun = dryRun
        let totalBytes = items.reduce(0) { $0 + max(0, $1.reclaimableBytes) }
        var processedBytes: Int64 = 0
        var freedBytes: Int64 = 0
        var skipped = 0
        var failed = 0

        for (index, item) in items.enumerated() {
            progress?(
                CleanProgress(
                    processed: index, total: items.count, processedBytes: processedBytes,
                    totalBytes: totalBytes, freedBytes: freedBytes, skipped: skipped, failed: failed,
                    currentPath: item.url.path, currentBytes: max(0, item.reclaimableBytes),
                    currentMode: item.mode, currentIsDirectory: !item.stamp.isRegularFile && !item.stamp.isSymlink))
            let outcome = clean(item)
            log.append(item, outcome, dryRun: dryRun)
            report.results.append(CleanResult(item: item, outcome: outcome, dryRun: dryRun))
            switch outcome {
            case .removed(let bytes), .trashed(let bytes):
                freedBytes += bytes
            case .skipped:
                skipped += 1
            case .failed:
                failed += 1
            }
            processedBytes += max(0, item.reclaimableBytes)
            if let recorder, (index + 1) % 16 == 0 {
                recorder.record(step: "clean", "progress: \(index + 1)/\(items.count) items")
            }
        }

        progress?(
            CleanProgress(
                processed: items.count, total: items.count, processedBytes: totalBytes,
                totalBytes: totalBytes, freedBytes: freedBytes, skipped: skipped, failed: failed,
                currentPath: "", currentBytes: 0, currentMode: .permanent, isFinal: true))

        if let recorder {
            recorder.record(
                step: "clean",
                "\(report.results.count) checked, \(report.freedBytes) bytes freed")
            if dryRun { recorder.record(step: "clean", "dry run: nothing was deleted") }
        }
        return report
    }

    func clean(_ item: ScanItem) -> CleanOutcome {
        guard item.risk != .informational else { return .skipped(.policy) }
        guard let current = FileStamp.read(item.url) else { return .skipped(.missing) }
        guard !current.isSymlink, current.inode == item.stamp.inode, current.size == item.stamp.size,
            current.modified == item.stamp.modified
        else { return .skipped(.changed) }
        guard policy.isDeletable(item.url) == .allowed else { return .skipped(.policy) }
        // Local Terraform state is user data: providers re-download, state does not. Refused in
        // both modes so a Trash sweep cannot lose it either.
        if TerraformState.holdsLocalState(item.url) { return .skipped(.localState) }
        if let owner = owner(item), isRunning(owner) { return .skipped(.appRunning) }
        if dryRun {
            return item.mode == .permanent ? .removed(item.reclaimableBytes) : .trashed(item.reclaimableBytes)
        }
        do {
            switch item.mode {
            case .permanent:
                try FileManager.default.removeItem(at: item.url)
                return .removed(item.reclaimableBytes)
            case .trash:
                try trash(item.url)
                return .trashed(item.reclaimableBytes)
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
