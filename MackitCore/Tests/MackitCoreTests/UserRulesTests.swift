import Foundation
import Testing

@testable import MackitCore

struct UserRulesTests {
    @Test func ruleCarriesTheFolderAsReviewTrash() throws {
        let dir = try TempDir()
        let folder = dir.url.appendingPathComponent("Downloads/old")
        let rule = UserRule(path: folder.path).rule
        #expect(rule.category == "user-rules")
        #expect(rule.roots == [folder.path])
        #expect(rule.title == "old")
        #expect(rule.risk == .review)
        #expect(rule.mode == .trash)
        #expect(rule.recursiveNames == nil)
        #expect(rule.wholeRoots == false)
    }

    @Test func ruleListsTheFolderChildrenOnce() async throws {
        let dir = try TempDir()
        try dir.file("Downloads/old/a.bin", bytes: 1_000_000)
        try dir.file("Downloads/old/b.bin", bytes: 2_000_000)
        let folder = dir.url.appendingPathComponent("Downloads/old")
        let rule = UserRule(path: folder.path).rule
        let result = try await RuleScanner(home: dir.url, rules: [rule]).scan(rule)
        #expect(Set(result.items.map(\.url.lastPathComponent)) == ["a.bin", "b.bin"])
        #expect(result.items.allSatisfy { $0.risk == .review && $0.mode == .trash })
        #expect(result.category == "user-rules")
    }

    @Test func ruleOutsideHomeScansWithoutTheOutsideSetting() async throws {
        let home = try TempDir()
        let outside = try TempDir()
        try outside.file("dump/blob", bytes: 1_000_000)
        let folder = outside.url.appendingPathComponent("dump")
        let rule = UserRule(path: folder.path).rule
        let result = try await RuleScanner(home: home.url, rules: [rule]).scan(rule)
        #expect(result.items.map(\.url.lastPathComponent) == ["blob"])
    }
}
