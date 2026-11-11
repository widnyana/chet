import Foundation
import Synchronization

final class LogTestClock: @unchecked Sendable {
    private let state = Mutex(Date(timeIntervalSince1970: 1_000_000))

    var now: Date {
        state.withLock { $0 }
    }

    func advance(_ seconds: TimeInterval) {
        state.withLock { $0 += seconds }
    }
}
