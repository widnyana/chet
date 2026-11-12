import ChetCore

/// Plain words for tweak state, risk, restarts, and history. One source, used by the list
/// and the details sheet.
enum TweakCopy {
    static let verificationNote =
        "Each change is checked by reading the value back. A failed change restores the earlier value."

    static func state(_ state: TweakState) -> String {
        switch state {
        case .on: "On"
        case .off: "Off"
        case .value(let text): text
        case .custom(let text): "Set to \(text)"
        case .unsupported(let reason): reason
        case .unknown(let reason): reason
        case .error: "Could not change"
        }
    }

    static func risk(_ risk: TweakRisk) -> String {
        switch risk {
        case .low: "Low risk"
        case .medium: "Medium risk"
        case .high: "High risk"
        }
    }

    static func processName(_ restart: TweakRestart) -> String {
        switch restart {
        case .none: ""
        case .finder: "Finder"
        case .dock: "Dock"
        case .systemUI: "SystemUIServer"
        case .login: ""
        }
    }

    /// The sentence in the details sheet.
    static func restart(_ restart: TweakRestart) -> String {
        switch restart {
        case .none: "Applies as soon as the change is written."
        case .finder: "Restart Finder to see the change."
        case .dock: "Restart the Dock to see the change."
        case .systemUI: "Restart the menu bar to see the change."
        case .login: "Sign out and back in to see the change."
        }
    }

    static func action(_ action: TweakRecord.Action) -> String {
        switch action {
        case .set: "Changed"
        case .reset: "Reset to the macOS default"
        case .rollback: "Reverted"
        }
    }

    static func value(_ value: TweakValue?) -> String {
        value?.display ?? "the macOS default"
    }

    static func defaultValue(_ value: TweakValue?) -> String {
        value.defaultDisplay
    }

    static func riskTone(_ risk: TweakRisk) -> StatusTone {
        switch risk {
        case .low: .neutral
        case .medium: .amber
        case .high: .red
        }
    }
}

extension TweakCopy {
    static let automationTitle = "Automation"
    static let automationPickerLabel = "When this app runs"
    static let automationBadge = "Automated"
    static let automationFilterTitle = "Automated"
    static let automationSettingsTitle = "Automation"
    static let automationRevertAll = "Revert all automated changes"
    static let automationOrphan = "This rule points at a tweak that no longer exists."
    static let automationConflict = "The value changed outside Chet, so the rule left it alone."
    static let automationCorrupt = "The automation file could not be read. Chet started with no rules."

    static func automationCount(_ count: Int) -> String {
        count == 1 ? "1 rule" : "\(count) rules"
    }
}
