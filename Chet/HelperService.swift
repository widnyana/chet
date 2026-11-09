import ChetCore
import Foundation
import ServiceManagement
import Synchronization

/// The registered root daemon. Registration is the only thing the app does on its own behalf;
/// every removal is a request the user confirmed, and the daemon decides what a root process
/// may touch.
enum HelperService {
    /// The daemon's status in plain words, so a view never names a ServiceManagement type.
    enum State: Equatable { case off, enabled, needsApproval, missing }

    private struct Cached {
        var available: Bool?
        var at = Date.distantPast
    }

    /// `status` is a call into the system daemon registry, and a table asks about availability
    /// once per row. Two seconds of reuse keeps a render from a hundred round trips without
    /// hiding an approval the user just made in System Settings.
    private static let cache = Mutex(Cached())
    private static let cacheLifetime: TimeInterval = 2

    static var service: SMAppService { .daemon(plistName: HelperGuard.plistName) }

    static var status: SMAppService.Status { service.status }

    static var state: State {
        switch status {
        case .enabled: .enabled
        case .requiresApproval: .needsApproval
        case .notFound: .missing
        default: .off
        }
    }

    /// True when a removal request may be made: the daemon is on, and the dry-run gate is off.
    /// The gate wins, so a preview build never registers, never calls, and never changes a file.
    static var isAvailable: Bool {
        let now = Date()
        let cached = cache.withLock { state -> Bool? in
            guard let value = state.available, now.timeIntervalSince(state.at) < cacheLifetime else {
                return nil
            }
            return value
        }
        if let cached { return cached }
        let fresh = !DryRun.enabled && status == .enabled
        cache.withLock { $0 = Cached(available: fresh, at: now) }
        return fresh
    }

    /// Drops the cached answer after the user turns the daemon on or off.
    static func invalidate() {
        cache.withLock { $0 = Cached() }
    }

    static func register() throws {
        try service.register()
        invalidate()
    }

    static func unregister() async throws {
        try await service.unregister()
        invalidate()
    }

    /// The approval lifetime the daemon gets, in seconds, from the stored setting.
    static var lifetimeSeconds: TimeInterval {
        let stored = UserDefaults.standard.object(forKey: ScanModel.helperLifetimeKey) as? Int ?? 10
        return TimeInterval(min(60, max(1, stored)) * 60)
    }

    /// One removal through the daemon. Returns `ok`, `refused:<reason>`, or `failed:<message>`.
    /// Blocks the calling thread; never call it from the main actor.
    static func remove(_ url: URL, bundleID: String) -> String {
        PrivilegedClient(lifetime: lifetimeSeconds).remove(url.path, bundleID: bundleID)
    }
}
