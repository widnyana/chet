import Foundation

public actor TweakWriter {
    public init() {}

    public func run(_ work: @Sendable () -> TweakChange) -> TweakChange {
        work()
    }
}

public enum RollbackPolicy {
    public static func target(history: [TweakRecord], ruleOwned: Set<String>) -> TweakRecord? {
        guard let last = history.last(where: { $0.error == nil }) else { return nil }
        return ruleOwned.contains(last.tweakID) ? nil : last
    }
}
