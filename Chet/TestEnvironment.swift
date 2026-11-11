import ChetCore
import Foundation

enum TestEnvironment {
    private static let environment = ProcessInfo.processInfo.environment

    static let isActive = environment[TestPaths.rootVariable] != nil

    static let paths: TestPaths = {
        guard isActive else { return .production() }
        guard let test = TestPaths.resolve(environment: environment) else {
            fatalError("\(TestPaths.rootVariable) must be an absolute path under a temporary directory")
        }
        return test
    }()

    static let auditLog = AuditLog(url: paths.logs.appendingPathComponent("clean.log"))

    nonisolated(unsafe) static let defaults: UserDefaults = {
        guard isActive else { return .standard }
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("the test preferences suite \(suiteName) could not be opened")
        }
        return defaults
    }()

    private static let suiteName = (Bundle.main.bundleIdentifier ?? "chet") + ".uitest"
}
