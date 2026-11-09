import Darwin
import Foundation

/// The one call the privileged helper serves. The app never hands it anything else: a list of
/// paths, the caller's bundle ID, and the approval lifetime the user picked.
@objc public protocol ChetHelperProtocol {
    func remove(
        _ paths: [String], bundleID: String, lifetime: Double,
        reply: @escaping ([String]) -> Void)
}

/// The path rules the helper applies to every removal. The app decides what to offer; the
/// helper decides what a root process may touch. Both read the same list, so a path the app
/// shows can never be refused for a reason the app does not already know.
public enum HelperGuard {
    public static let machServiceName = "id.web.widnyana.chet.helper"
    public static let plistName = "id.web.widnyana.chet.helper.plist"

    /// The only trees a root process removes from. A whole system tree is never a root.
    public static let roots = [
        "/Library/Caches", "/Library/Logs", "/Library/Application Support",
        "/Library/Preferences", "/Library/LaunchAgents", "/Library/LaunchDaemons",
    ]

    /// Paths no helper call may reach, whatever the roots say.
    public static let protected = [
        "/System", "/usr", "/bin", "/sbin", "/private/etc", "/private/var/db",
        "/private/var/root", "/Library/Apple", "/Library/Extensions",
        "/Library/Frameworks", "/Library/Keychains", "/Library/Mail", "/Library/Messages",
    ]

    /// Nil means the helper may remove the path. `roots` is injectable so a test can use a
    /// temp folder. Reasons are literal and reach the audit log unchanged.
    ///
    /// The helper never re-derives app ownership: Chet revalidates the item against its own
    /// catalog, and only this app can reach the daemon's mach service (the listener pins the
    /// code-signing requirement to its identifier). These rules bound damage; the catalog
    /// decides relevance.
    public static func refusal(path raw: String, roots: [String] = HelperGuard.roots) -> String? {
        guard !raw.isEmpty, raw.hasPrefix("/") else { return "not absolute" }
        guard !raw.split(separator: "/").contains("..") else { return "path traversal" }
        // No Foundation standardization: it rewrites the `/private` prefix, which would make
        // every real temp path look like a different path than the one on disk.
        let rawPath = URL(fileURLWithPath: raw).path
        guard !isProtected(rawPath) else { return "protected" }
        // Every folder above the leaf must be the real one: a link anywhere in the chain would
        // send the removal somewhere else. `realpath(3)` is the only check that agrees with the
        // directory walk.
        let rawParent = (rawPath as NSString).deletingLastPathComponent
        let parent = FS.canonicalPath(URL(fileURLWithPath: rawParent))
        guard parent == rawParent else { return "symlink" }
        let path = parent + "/" + (rawPath as NSString).lastPathComponent
        var status = stat()
        guard lstat(path, &status) == 0 else { return "missing" }
        guard (status.st_mode & S_IFMT) != S_IFLNK else { return "symlink" }
        // The root folder itself is not removable: only its children are.
        guard roots.contains(where: { path.hasPrefix($0 + "/") }) else {
            return "outside allowed roots"
        }
        return nil
    }

    static func isProtected(_ path: String) -> Bool {
        protected.contains { path == $0 || path.hasPrefix($0 + "/") }
    }
}

/// The bounded approval a helper run gets. The clock starts on the first removal request; the
/// helper exits at the deadline, so the next request is a new session, not an extension.
public struct HelperSession: Sendable {
    public let lifetime: TimeInterval
    private let clock: @Sendable () -> Date
    private var deadline: Date?

    public init(lifetime: TimeInterval, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.lifetime = lifetime.isFinite ? min(3600, max(60, lifetime)) : 600
        self.clock = clock
        self.deadline = nil
    }

    /// False when the session is over. Starts the clock on the first call.
    public mutating func allow() -> Bool {
        let now = clock()
        let end = deadline ?? now.addingTimeInterval(lifetime)
        deadline = end
        return now < end
    }

    /// Seconds left before the helper exits; the full lifetime before the first request.
    public func remaining() -> TimeInterval {
        guard let deadline else { return lifetime }
        return max(0, deadline.timeIntervalSince(clock()))
    }
}

/// The app-side client. One call, one bounded wait, one answer:
/// `ok`, `refused:<reason>`, or `failed:<message>`.
public struct PrivilegedClient: Sendable {
    public let lifetime: TimeInterval

    public init(lifetime: TimeInterval) {
        self.lifetime = lifetime
    }

    /// Blocks up to 10 seconds waiting for the helper. Call it from a background thread, never
    /// from the main actor.
    public func remove(_ path: String, bundleID: String) -> String {
        let connection = NSXPCConnection(machServiceName: HelperGuard.machServiceName)
        connection.remoteObjectInterface = NSXPCInterface(with: ChetHelperProtocol.self)
        connection.resume()
        defer { connection.invalidate() }
        let reply = ReplyBox()
        let semaphore = DispatchSemaphore(value: 0)
        guard
            let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                reply.set("failed:\(error.localizedDescription)")
                semaphore.signal()
            }) as? ChetHelperProtocol
        else { return "failed:no connection" }
        proxy.remove([path], bundleID: bundleID, lifetime: lifetime) { answers in
            reply.set(answers.first ?? "failed:no reply")
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 10)
        return reply.value ?? "failed:no reply"
    }
}

/// One answer, written once. The error handler and the reply block race by design.
private final class ReplyBox: @unchecked Sendable {
    private let lock = NSLock()
    private var text: String?

    var value: String? {
        lock.lock()
        defer { lock.unlock() }
        return text
    }

    func set(_ next: String) {
        lock.lock()
        if text == nil { text = next }
        lock.unlock()
    }
}
