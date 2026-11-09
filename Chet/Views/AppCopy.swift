import ChetCore

/// Plain names for app parts, how strongly a file belongs to an app, and why an item
/// was left alone. The core's `title` strings are used by logs and tests.
enum AppCopy {
    static func component(_ kind: AppComponentKind) -> String {
        switch kind {
        case .application: "The app"
        case .applicationSupport: "Saved app data"
        case .preferences: "Settings"
        case .caches: "Caches"
        case .logs: "Logs"
        case .containers: "App storage"
        case .groupContainers: "Shared app storage"
        case .savedApplicationState: "Window state"
        case .cookies: "Cookies"
        case .applicationScripts: "Scripts"
        case .launchAgents: "Background items"
        case .launchDaemons: "System background items"
        case .webKit: "Web data"
        case .other: "Other files"
        }
    }

    static func ownership(_ ownership: AppOwnership) -> String {
        switch ownership {
        case .exclusive: "Belongs to this app"
        case .probable: "Probably belongs"
        case .shared: "Shared with another app"
        case .privileged: "Needs an administrator"
        case .systemProtected: "Protected by macOS"
        }
    }

    static func skip(_ reason: UninstallSkipReason) -> String {
        switch reason {
        case .missing: "Already gone"
        case .changed: "Changed since the scan"
        case .policy: "Protected by Chet"
        case .appRunning: "The app is open"
        case .requiresAdmin: "Needs an administrator"
        case .shared: "Shared with another app"
        case .protected: "Protected by macOS"
        case .appMissing: "The app is gone"
        case .notSelected: "Kept"
        case .cancelled: "Cancelled"
        }
    }
}
