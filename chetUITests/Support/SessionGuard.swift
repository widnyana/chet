import AppKit

enum SessionGuardError: Error, LocalizedError, CustomStringConvertible, Equatable {
    case dryRunMissing
    case userInstanceRunning(String)
    case helperRunning(String)
    case helperStartTimeUnreadable([pid_t])

    var errorDescription: String? { description }

    var description: String {
        switch self {
        case .dryRunMissing:
            "tests require DRY_RUN=1"
        case .userInstanceRunning(let detail):
            "a chet instance outside the test build is running: \(detail)"
        case .helperRunning(let detail):
            "chet-helper was launched during the test run: \(detail)"
        case .helperStartTimeUnreadable(let pids):
            "could not read the start time of chet-helper: \(pids.map(String.init).joined(separator: ", "))"
        }
    }
}

@MainActor
enum SessionGuard {
    private static let applicationBundleIdentifier = "id.web.widnyana.chet"
    private static let sessionStart = Date()

    static func assertDryRun() throws {
        let raw = ProcessInfo.processInfo.environment["DRY_RUN"]?
            .trimmingCharacters(in: .whitespaces).lowercased()
        guard raw == "1" || raw == "true" else {
            throw SessionGuardError.dryRunMissing
        }
    }

    static func assertNoUserInstance() throws {
        let applications = NSRunningApplication.runningApplications(
            withBundleIdentifier: applicationBundleIdentifier)
        let offenders = applications.filter { application in
            guard let path = application.bundleURL?.standardizedFileURL.path else { return true }
            return !isTestBuild(path)
        }
        guard offenders.isEmpty else {
            let detail = offenders.map {
                "\($0.processIdentifier) \($0.bundleURL?.path ?? "unknown bundle path")"
            }.joined(separator: ", ")
            throw SessionGuardError.userInstanceRunning(detail)
        }
    }

    nonisolated static func isTestBuild(_ path: String) -> Bool {
        path.contains("/.build/xc/Build/Products/")
    }

    static func assertNoHelper() throws {
        let pids = pgrep("chet-helper")
        guard !pids.isEmpty else { return }
        var launched: [(pid: pid_t, start: Date)] = []
        var unreadable: [pid_t] = []
        for pid in pids {
            guard let start = processStart(pid) else {
                unreadable.append(pid)
                continue
            }
            if start.timeIntervalSince1970 >= sessionStart.timeIntervalSince1970.rounded(.down) {
                launched.append((pid, start))
            }
        }
        guard unreadable.isEmpty else {
            throw SessionGuardError.helperStartTimeUnreadable(unreadable)
        }
        guard launched.isEmpty else {
            let detail = launched.map {
                "\($0.pid) started \($0.start)"
            }.joined(separator: ", ")
            throw SessionGuardError.helperRunning(detail)
        }
    }

    private static func pgrep(_ name: String) -> [pid_t] {
        guard let output = run("/usr/bin/pgrep", ["-x", name]) else { return [] }
        return output.split(whereSeparator: \.isWhitespace).compactMap { pid_t($0) }
    }

    private static func processStart(_ pid: pid_t) -> Date? {
        guard let output = run("/bin/ps", ["-p", "\(pid)", "-o", "lstart="]) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return formatter.date(from: output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func run(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
