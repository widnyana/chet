import Foundation
import Synchronization

/// Cooperative pause for a running scan. The scan task calls `wait()` between steps and
/// between roots; while paused it sleeps in short ticks so cancellation (Stop) always wins
/// promptly. Polling keeps the gate free of continuation races — the paused state is idle
/// by definition, so a 100 ms tick costs nothing.
public final class ScanPauseGate: Sendable {
    private let paused = Mutex(false)

    public init() {}

    public var isPaused: Bool { paused.withLock { $0 } }

    public func setPaused(_ value: Bool) {
        paused.withLock { $0 = value }
    }

    /// Returns when the gate is open. Throws CancellationError when the scan is stopped.
    public func wait() async throws {
        while isPaused {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(100))
        }
    }
}
