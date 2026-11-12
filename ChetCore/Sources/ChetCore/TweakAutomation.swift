import Foundation

public enum TriggerKind: Codable, Sendable, Hashable {
    case app(bundleID: String, name: String)

    public var bundleID: String {
        switch self {
        case .app(let bundleID, _): bundleID
        }
    }

    public var name: String {
        switch self {
        case .app(_, let name): name
        }
    }
}

public struct TweakRule: Codable, Sendable, Identifiable, Equatable {
    public typealias Desired = TweakDesired

    public let id: UUID
    public let tweakID: String
    public let trigger: TriggerKind
    public let desired: TweakDesired
    public let isEnabled: Bool

    public init(
        id: UUID = UUID(), tweakID: String, trigger: TriggerKind, desired: TweakDesired,
        isEnabled: Bool
    ) {
        self.id = id
        self.tweakID = tweakID
        self.trigger = trigger
        self.desired = desired
        self.isEnabled = isEnabled
    }
}

public struct AutomationFile<Payload: Codable & Sendable>: Codable, Sendable {
    public let version: Int
    public let payload: Payload

    public init(version: Int = 1, payload: Payload) {
        self.version = version
        self.payload = payload
    }
}

public struct TweakCurrent: Sendable, Equatable {
    public let tweakID: String
    public let value: TweakValue?

    public init(tweakID: String, value: TweakValue?) {
        self.tweakID = tweakID
        self.value = value
    }
}

public enum AutomationDecision: Sendable, Equatable {
    case apply(ruleID: UUID, value: TweakValue?)
    case revert(tweakID: String, value: TweakValue?)
    case keep(tweakID: String)
    case orphan(tweakID: String)
    case conflict(tweakID: String)
}

public enum AutomationPlanner {
    public static func desired(rules: [TweakRule], running: Set<String>) -> [UUID: Bool] {
        Dictionary(
            uniqueKeysWithValues: rules.map { rule in
                (rule.id, rule.isEnabled && running.contains(rule.trigger.bundleID))
            })
    }

    public static func plan(
        rules: [TweakRule], running: Set<String>, state: WALState, current: [TweakCurrent]
    ) -> [AutomationDecision] {
        let currents = Dictionary(
            current.map { ($0.tweakID, $0.value) }, uniquingKeysWith: { _, last in last })
        return rules.map { rule in
            guard let tweak = TweakCatalog.tweak(id: rule.tweakID),
                case .toggle = tweak.control
            else { return .orphan(tweakID: rule.tweakID) }
            guard let currentValue = currents[rule.tweakID] else {
                return .keep(tweakID: rule.tweakID)
            }
            let desiredValue = tweak.control.resolvedValue(for: rule.desired)
            if rule.isEnabled && running.contains(rule.trigger.bundleID) {
                if currentValue == desiredValue { return .keep(tweakID: rule.tweakID) }
                return .apply(ruleID: rule.id, value: desiredValue)
            }
            guard let applied = state.applied[rule.tweakID] else {
                return .keep(tweakID: rule.tweakID)
            }
            if currentValue == applied.baseline { return .keep(tweakID: rule.tweakID) }
            if currentValue == desiredValue {
                return .revert(tweakID: rule.tweakID, value: applied.baseline)
            }
            return .conflict(tweakID: rule.tweakID)
        }
    }
}
