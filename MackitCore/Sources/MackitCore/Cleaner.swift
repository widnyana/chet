import AppKit
import Foundation

public enum SkipReason: String, Sendable {
    case missing, changed, policy, appRunning
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

    public func clean(_ items: [ScanItem]) -> CleanReport {
        var report = CleanReport()
        report.dryRun = dryRun
        for (index, item) in items.enumerated() {
            let outcome = clean(item)
            log.append(item, outcome, dryRun: dryRun)
            report.results.append(CleanResult(item: item, outcome: outcome, dryRun: dryRun))
            if let recorder, (index + 1) % 16 == 0 {
                recorder.record(step: "clean", "progress: \(index + 1)/\(items.count) items")
            }
        }
        if let recorder {
            recorder.record(
                step: "clean",
                "\(report.results.count) checked, \(report.freedBytes) bytes freed")
            if dryRun { recorder.record(step: "clean", "dry run: nothing was deleted") }
        }
        return report
    }

    func clean(_ item: ScanItem) -> CleanOutcome {
        guard let current = FileStamp.read(item.url) else { return .skipped(.missing) }
        guard !current.isSymlink, current.inode == item.stamp.inode, current.size == item.stamp.size,
            current.modified == item.stamp.modified
        else { return .skipped(.changed) }
        guard policy.isDeletable(item.url) == .allowed else { return .skipped(.policy) }
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
