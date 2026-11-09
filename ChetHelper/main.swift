import ChetCore
import Darwin
import Foundation

/// The root daemon. launchd starts it on the first removal request and it exits at the end of
/// the approval the user granted, so no privileged process stays resident.
private final class HelperExported: NSObject, ChetHelperProtocol {
    /// One bounded session per process. The first request starts the clock; a request that
    /// arrives after the deadline is refused and the process goes away.
    private let lock = NSLock()
    private var session: HelperSession?

    func remove(
        _ paths: [String], bundleID: String, lifetime: Double,
        reply: @escaping ([String]) -> Void
    ) {
        lock.lock()
        var current = session ?? HelperSession(lifetime: lifetime)
        let allowed = current.allow()
        session = current
        lock.unlock()

        guard allowed else {
            reply(paths.map { _ in "refused:expired" })
            // Give the reply a tick to leave the connection before the process ends.
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) { exit(0) }
            return
        }

        let answers = paths.map { path -> String in
            if let refusal = HelperGuard.refusal(path: path) { return "refused:\(refusal)" }
            do {
                // Permanent removal, never the Trash: root-owned data has no per-user Trash.
                try FileManager.default.removeItem(atPath: path)
                return "ok"
            } catch {
                return "failed:\(error.localizedDescription)"
            }
        }
        reply(answers)
        let remaining = current.remaining()
        DispatchQueue.global().asyncAfter(deadline: .now() + remaining) { exit(0) }
    }
}

private final class HelperListener: NSObject, NSXPCListenerDelegate {
    private let exported = HelperExported()

    func listener(
        _ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        // Only this app may talk to the daemon. The requirement is not loosened: a broader
        // anchor would let any signed process ask for root removals.
        connection.setCodeSigningRequirement("identifier \"id.web.widnyana.chet\"")
        connection.exportedInterface = NSXPCInterface(with: ChetHelperProtocol.self)
        connection.exportedObject = exported
        connection.resume()
        return true
    }
}

let listener = NSXPCListener(machServiceName: HelperGuard.machServiceName)
// `NSXPCListener.delegate` is weak: the listener must own a strong reference elsewhere.
private let delegate = HelperListener()
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
