import Foundation
import Testing

@testable import ChetCore

@Suite(.serialized)
struct DryRunRefusalTests {
    init() throws {
        try TestGuard.requireDryRun()
    }

    @Test func unsetAndZeroThrow() {
        for environment in [[:], ["DRY_RUN": "0"]] {
            do {
                try TestGuard.requireDryRun(environment: environment)
                Issue.record("expected dryRunMissing for \(environment)")
            } catch let error as TestGuardError {
                #expect(error == .dryRunMissing)
                #expect(error.description == "tests require DRY_RUN=1")
            } catch {
                Issue.record("unexpected error: \(error)")
            }
        }
    }

    @Test func trueValuesPass() throws {
        try TestGuard.requireDryRun(environment: ["DRY_RUN": "1"])
        try TestGuard.requireDryRun(environment: ["DRY_RUN": "true"])
        try TestGuard.requireDryRun(environment: ["DRY_RUN": "TRUE"])
    }

    @Test func scratchRootResolvesUnderTheTemporaryDirectory() throws {
        let dir = try TempDir()
        #expect(try TestGuard.requireScratchRoot(dir.url.path).path == dir.url.path)
        do {
            _ = try TestGuard.requireScratchRoot("relative")
            Issue.record("expected scratchRootInvalid")
        } catch let error as TestGuardError {
            #expect(error == .scratchRootInvalid("relative"))
        }
        do {
            _ = try TestGuard.requireScratchRoot(FileManager.default.homeDirectoryForCurrentUser.path)
            Issue.record("expected pathOutsideScratchRoot")
        } catch let error as TestGuardError {
            guard case .pathOutsideScratchRoot = error else {
                Issue.record("unexpected guard error: \(error)")
                return
            }
        }
    }

    @Test func writeOutsideTheScratchRootIsNamed() throws {
        let container = try TempDir()
        let root = container.url.appendingPathComponent("scratch", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let outside = container.url.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let probe = outside.appendingPathComponent(".chet-guard-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: container.url) }
        do {
            try TestGuard.assertNoMutation(outside: root) {
                try Data("probe".utf8).write(to: probe)
            }
            Issue.record("expected mutationOutsideScratchRoot")
        } catch let error as TestGuardError {
            guard case .mutationOutsideScratchRoot(let path) = error else {
                Issue.record("unexpected guard error: \(error)")
                return
            }
            #expect(path == probe.path)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test func dryRunCleanKeepsBytesAndModificationTime() throws {
        let container = try TempDir()
        let root = container.url.appendingPathComponent("scratch", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = try container.file("scratch/cache/blob", bytes: 4_096)
        let before = TestGuard.snapshot(of: [file.path])
        let modified = try #require(
            (try FileManager.default.attributesOfItem(atPath: file.path))[.modificationDate]
                as? Date)
        let stamp = try #require(FileStamp.read(file))
        let item = ScanItem(
            url: file, categoryID: "test", risk: .safe, mode: .permanent, reclaimableBytes: 4_096,
            stamp: stamp)
        var report: CleanReport?
        var cleaner = Cleaner(
            policy: container.policy,
            log: AuditLog(url: root.appendingPathComponent("clean.log")), dryRun: true)
        cleaner.isRunning = { _ in false }
        report = cleaner.clean([item])
        let result = try #require(report)
        #expect(result.dryRun)
        #expect(result.freedBytes == 4_096)
        #expect(result.results.first?.outcome == .removed(4_096))
        #expect(try Data(contentsOf: file).count == 4_096)
        #expect(
            (try FileManager.default.attributesOfItem(atPath: file.path))[.modificationDate]
                as? Date == modified)
        #expect(TestGuard.snapshot(of: [file.path]) == before)
    }
}
