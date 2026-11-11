import AppKit
import XCTest

enum FocusGuardError: Error, LocalizedError, CustomStringConvertible, Equatable {
    case notForeground(String)
    case foregroundLost(expected: String, actual: String)

    var errorDescription: String? { description }

    var description: String {
        switch self {
        case .notForeground(let state):
            "the app under test is not in the foreground: \(state)"
        case .foregroundLost(let expected, let actual):
            "focus moved from \(expected) to \(actual); the run stopped before sending input"
        }
    }
}

enum FocusGuard {
    static let appBundleIdentifier = "id.web.widnyana.chet"

    static func requireForeground(_ app: XCUIApplication) throws {
        guard app.state == .runningForeground else {
            throw FocusGuardError.notForeground(stateName(app.state))
        }
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none"
        guard front == appBundleIdentifier else {
            throw FocusGuardError.foregroundLost(expected: appBundleIdentifier, actual: front)
        }
    }

    static func assertStillForeground(_ app: XCUIApplication) throws {
        try requireForeground(app)
    }

    private static func stateName(_ state: XCUIApplication.State) -> String {
        switch state {
        case .unknown: "unknown"
        case .notRunning: "not running"
        case .runningBackground: "running in the background"
        case .runningForeground: "running in the foreground"
        @unknown default: "unrecognised state"
        }
    }
}
