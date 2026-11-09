import ChetCore

/// Plain words for tweak state, risk, restarts, and history. One source, used by the list
/// and the details sheet.
enum TweakCopy {
    static func state(_ state: TweakState) -> String {
        switch state {
        case .on: "On"
        case .off: "Off"
        case .value(let text): text
        case .custom(let text): "Set to \(text)"
        case .unsupported(let reason): reason
        case .unknown(let reason): reason
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

    static func riskTone(_ risk: TweakRisk) -> StatusTone {
        switch risk {
        case .low: .neutral
        case .medium: .amber
        case .high: .red
        }
    }
}
