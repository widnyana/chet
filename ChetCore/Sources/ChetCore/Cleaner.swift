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
    /// The reason a skipped row was skipped; nil for removed, trashed, and failed rows.
    public let refusal: RefusalReason?
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
    /// Set when the batch was refused before the first removal; `results` is then empty.
    public var refusal: RefusalReason?
    /// True when the pass stopped after the current item because the user cancelled.
    public var cancelled = false
    /// The ledger operation this pass wrote, when it moved anything to the Trash.
    public var operationID: UUID?

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
    /// Every root a batch may touch. The batch guard refuses a path outside all of them.
    public var roots: [URL]
    /// Cooperative cancel: checked before each item. Items already removed stay removed.
    public var isCancelled: @Sendable () -> Bool = { false }
    /// Records every Trash-mode removal. Nil disables the ledger.
    public var ledger: TrashLedger?
    /// Bundle ID of the app that owns an item, if any.
    public var owner: @Sendable (ScanItem) -> String? = { _ in nil }
    public var isRunning: @Sendable (String) -> Bool = { id in
        !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
    }
    public var trash: @Sendable (URL) throws -> URL? = { url in
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        return resulting as URL?
    }
    /// Root-owned items. Set only when the helper is registered and the dry-run gate is off;
    /// without it a `requiresAdmin` item is a policy skip.
    public var privileged: (@Sendable (ScanItem) -> CleanOutcome)?

    public init(
        policy: SafetyPolicy, log: AuditLog = AuditLog(), recorder: FlightRecorder? = nil, dryRun: Bool,
        roots: [URL]? = nil
    ) {
        self.policy = policy
        self.log = log
        self.recorder = recorder
        self.dryRun = dryRun
        self.roots =
            roots
            ?? ([URL(fileURLWithPath: policy.home)]
                + policy.externalRoots.sorted().map(URL.init(fileURLWithPath:)))
    }

    public func clean(
        _ items: [ScanItem],
        progress: (@Sendable (CleanProgress) -> Void)? = nil
    ) -> CleanReport {
        let guardReport = BatchGuard.validate(items, policy: policy, roots: roots)
        if let refusal = guardReport.refusal {
            var report = CleanReport()
            report.dryRun = dryRun
            report.refusal = refusal
            VerboseLog.event(
                .warn, .clean, .cleanRefusedBatch,
                .count(.items, items.count), .code(.outcome, .outcomeRefused))
            VerboseLog.flush()
            return report
        }
        var report = CleanReport()
        report.dryRun = dryRun
        let totalBytes = items.reduce(0) { $0 + max(0, $1.reclaimableBytes) }
        var processedBytes: Int64 = 0
        var freedBytes: Int64 = 0
        var skipped = 0
        var failed = 0
        var removed = 0
        var trashed = 0
        var dryRunCount = 0
        var processedCount = 0
        var trashedEntries: [(item: ScanItem, url: URL)] = []
        let started = Date()

        VerboseLog.event(
            .info, .clean, .cleanStarted,
            .count(.items, items.count), .bytes(.bytes, totalBytes),
            .code(.mode, .modePermanent), .flag(.dryRun, dryRun))
        VerboseLog.flush()

        for (index, item) in items.enumerated() {
            if isCancelled() {
                report.cancelled = true
                break
            }
            progress?(
                CleanProgress(
                    processed: index, total: items.count, processedBytes: processedBytes,
                    totalBytes: totalBytes, freedBytes: freedBytes, skipped: skipped, failed: failed,
                    currentPath: item.url.path, currentBytes: max(0, item.reclaimableBytes),
                    currentMode: item.mode, currentIsDirectory: !item.stamp.isRegularFile && !item.stamp.isSymlink))
            let (outcome, refusal, trashedURL) = clean(item)
            log.append(item, outcome, dryRun: dryRun, reason: refusal)
            report.results.append(
                CleanResult(item: item, outcome: outcome, dryRun: dryRun, refusal: refusal))
            switch outcome {
            case .removed(let bytes):
                freedBytes += bytes
                removed += 1
                if dryRun { dryRunCount += 1 }
            case .trashed(let bytes):
                freedBytes += bytes
                trashed += 1
                if dryRun { dryRunCount += 1 }
                if let trashedURL { trashedEntries.append((item, trashedURL)) }
            case .skipped:
                skipped += 1
            case .failed:
                failed += 1
            }
            processedBytes += max(0, item.reclaimableBytes)
            processedCount += 1
            if let recorder, (index + 1) % 16 == 0 {
                recorder.record(step: "clean", "progress: \(index + 1)/\(items.count) items")
            }
        }

        if let ledger, !dryRun, !trashedEntries.isEmpty {
            let operation = TrashOperation(
                entries: trashedEntries.map { entry in
                    TrashOperation.Entry(
                        originalPath: entry.item.url.path,
                        trashedPath: entry.url.path,
                        bytes: entry.item.reclaimableBytes,
                        categoryID: entry.item.categoryID)
                })
            ledger.append(operation)
            report.operationID = operation.id
        }

        if report.cancelled {
            VerboseLog.event(
                .info, .clean, .cleanCancelled,
                .count(.removed, removed), .count(.skipped, skipped), .count(.failed, failed),
                .code(.outcome, .outcomeCancelled))
            VerboseLog.flush()
        }

        progress?(
            CleanProgress(
                processed: processedCount, total: items.count, processedBytes: processedBytes,
                totalBytes: totalBytes, freedBytes: freedBytes, skipped: skipped, failed: failed,
                currentPath: "", currentBytes: 0, currentMode: .permanent, isFinal: true))

        VerboseLog.event(
            .info, .clean, .cleanFinished,
            .count(.removed, removed), .count(.trashed, trashed),
            .count(.skipped, skipped), .count(.failed, failed),
            .count(.dryRunCount, dryRunCount),
            .count(.errnoSamples, 0))
        VerboseLog.flush()
        VerboseLog.event(
            .info, .clean, .cleanSummary,
            .count(.items, report.results.count), .bytes(.freed, report.freedBytes),
            .flag(.dryRun, dryRun),
            .durationMS(.durationMS, Int(Date().timeIntervalSince(started) * 1_000)))

        if let recorder {
            recorder.record(
                step: "clean",
                "\(report.results.count) checked, \(report.freedBytes) bytes freed")
            if dryRun { recorder.record(step: "clean", "dry run: nothing was deleted") }
        }
        return report
    }

    func clean(_ item: ScanItem) -> (CleanOutcome, RefusalReason?, URL?) {
        guard item.risk != .informational else { return (.skipped(.policy), .informational, nil) }
        guard let current = FileStamp.read(item.url) else { return (.skipped(.missing), .missing, nil) }
        guard !current.isSymlink, current.inode == item.stamp.inode, current.size == item.stamp.size,
            current.modified == item.stamp.modified
        else { return (.skipped(.changed), .changed, nil) }
        let denial = policy.denialReason(for: item.url)
        guard denial == nil else {
            VerboseLog.event(
                .warn, .clean, .cleanRefused,
                .basename(.item, Basename(path: item.url.path)), .code(.refusal, .refusal))
            return (.skipped(.policy), denial, nil)
        }
        // Local Terraform state is user data: providers re-download, state does not. Refused in
        // both modes so a Trash sweep cannot lose it either.
        if TerraformState.holdsLocalState(item.url) { return (.skipped(.localState), .localState, nil) }
        if let owner = owner(item), isRunning(owner) { return (.skipped(.appRunning), .appRunning, nil) }
        if item.requiresAdmin {
            if dryRun { return (.removed(item.reclaimableBytes), nil, nil) }
            guard let privileged else { return (.skipped(.policy), .protectedFolder, nil) }
            return (privileged(item), nil, nil)
        }
        if dryRun {
            return item.mode == .permanent
                ? (.removed(item.reclaimableBytes), nil, nil)
                : (.trashed(item.reclaimableBytes), nil, nil)
        }
        do {
            switch item.mode {
            case .permanent:
                try FileManager.default.removeItem(at: item.url)
                return (.removed(item.reclaimableBytes), nil, nil)
            case .trash:
                let trashed = try trash(item.url)
                return (.trashed(item.reclaimableBytes), nil, trashed)
            }
        } catch {
            return (.failed(error.localizedDescription), nil, nil)
        }
    }
}
