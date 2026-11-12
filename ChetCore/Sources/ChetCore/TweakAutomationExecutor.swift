import Foundation

public enum AutomationEngineOutcome: Sendable, Equatable {
    case applied(recorded: TweakRecord?)
    case unchanged
    case refused(String)
    case failed(String)
}

public protocol TweakAutomationEngine: Sendable {
    func current(tweakID: String) async -> TweakCurrent?
    func apply(tweakID: String, value: TweakValue?) async -> AutomationEngineOutcome
    func revert(tweakID: String, to value: TweakValue?) async -> AutomationEngineOutcome
}

public struct AutomationExecutor: Sendable {
    public let rules: [TweakRule]
    public let state: WALState
    public let engine: TweakAutomationEngine
    public let dryRun: Bool

    public init(rules: [TweakRule], state: WALState, engine: TweakAutomationEngine, dryRun: Bool) {
        self.rules = rules
        self.state = state
        self.engine = engine
        self.dryRun = dryRun
    }

    public func reconcile(
        running: Set<String>
    ) async -> (state: WALState, decisions: [AutomationDecision]) {
        var current: [TweakCurrent] = []
        for rule in rules {
            if let reading = await engine.current(tweakID: rule.tweakID) {
                current.append(reading)
            }
        }
        let decisions = AutomationPlanner.plan(
            rules: rules, running: running, state: state, current: current)
        guard !dryRun else { return (state, decisions) }

        var next = state
        for decision in decisions {
            switch decision {
            case .apply(let ruleID, let value):
                guard let rule = rules.first(where: { $0.id == ruleID }) else { continue }
                let baseline = current.first { $0.tweakID == rule.tweakID }?.value
                next.applied[rule.tweakID] = WALState.Applied(
                    ruleID: ruleID, tweakID: rule.tweakID, appliedValue: value, baseline: baseline,
                    baselineSource: "unavailable", phase: "applying", appliedAt: Date(),
                    conflict: nil)
                let outcome = await engine.apply(tweakID: rule.tweakID, value: value)
                switch outcome {
                case .applied(let record):
                    next.applied[rule.tweakID]?.phase = "applied"
                    next.applied[rule.tweakID]?.baselineSource =
                        record == nil ? "unavailable" : "engine"
                case .unchanged:
                    next.applied[rule.tweakID]?.phase = "applied"
                    next.applied[rule.tweakID]?.baselineSource = "alreadyActive"
                case .refused, .failed:
                    next.applied.removeValue(forKey: rule.tweakID)
                }
            case .revert(let tweakID, let value):
                guard var entry = next.applied[tweakID] else { continue }
                entry.phase = "reverting"
                next.applied[tweakID] = entry
                let outcome = await engine.revert(tweakID: tweakID, to: value)
                switch outcome {
                case .applied, .unchanged:
                    next.applied.removeValue(forKey: tweakID)
                case .refused, .failed:
                    break
                }
            case .keep, .orphan, .conflict:
                break
            }
        }
        return (next, decisions)
    }
}

public struct AutomationSession: Sendable {
    public let loadRules: @Sendable () -> [TweakRule]
    public let loadState: @Sendable () -> WALState
    public let running: @Sendable () -> Set<String>
    public let reconcile: @Sendable (Set<String>) async -> (state: WALState, decisions: [AutomationDecision])

    public init(
        loadRules: @Sendable @escaping () -> [TweakRule],
        loadState: @Sendable @escaping () -> WALState,
        running: @Sendable @escaping () -> Set<String>,
        reconcile:
            @Sendable @escaping (Set<String>) async -> (
                state: WALState, decisions: [AutomationDecision]
            )
    ) {
        self.loadRules = loadRules
        self.loadState = loadState
        self.running = running
        self.reconcile = reconcile
    }

    public func start() async -> (state: WALState, decisions: [AutomationDecision]) {
        _ = loadRules()
        _ = loadState()
        let running = running()
        return await reconcile(running)
    }
}
