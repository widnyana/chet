import Foundation
import Synchronization

public enum VerboseLog {
    #if DEBUG
        public static let enabled: Bool = isEnabled(environment: ProcessInfo.processInfo.environment)

        static func isEnabled(environment: [String: String]) -> Bool {
            DryRun.parse(environment["CHET_VERBOSE"])
        }
    #else
        public static let enabled = false

        static func isEnabled(environment: [String: String]) -> Bool { false }
    #endif

    private static let slot = Mutex<ActivityLog?>(nil)

    public static func install(_ writer: ActivityLog?) {
        slot.withLock { $0 = writer }
    }

    public static var isInstalled: Bool {
        slot.withLock { $0 != nil }
    }

    public static func event(
        _ level: LogLevel, _ category: LogCategory, _ message: LogMessage, _ fields: LogField?...
    ) {
        guard let writer = slot.withLock({ $0 }) else { return }
        writer.append(level, category, message, fields.compactMap { $0 })
    }

    public static func flush() {
        slot.withLock { $0?.flush() }
    }

    public static func shutdown() {
        slot.withLock { writer in
            writer?.flush()
            writer?.close()
            writer = nil
        }
    }
}
