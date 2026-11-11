import Foundation
import Testing

@testable import ChetCore

struct LogTypesTests {
    private func encoded(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    @Test func codesKeepTheirAppendOnlyValues() {
        #expect(LogCode.stepScan.rawValue == 1)
        #expect(LogCode.stepTaggedCaches.rawValue == 10)
        #expect(LogCode.categoryCaches.rawValue == 100)
        #expect(LogCode.categoryOther.rawValue == 115)
        #expect(LogCode.modeTrash.rawValue == 201)
        #expect(LogCode.outcomeCancelled.rawValue == 305)
        #expect(LogCode.sizeBasisAllocated.rawValue == 400)
        #expect(LogCode.settingsKeyUserRules.rawValue == 503)
        #expect(LogCode.verificationFailed.rawValue == 601)
    }

    @Test func basenameAccepts128BytesOnly() {
        #expect(Basename(String(repeating: "a", count: 128)) != nil)
        #expect(Basename(String(repeating: "a", count: 129)) == nil)
        #expect(Basename("dir/file.txt") == nil)
        #expect(Basename("file.txt")?.value == "file.txt")
        #expect(Basename(path: "/tmp/example.txt")?.value == "example.txt")
        #expect(Basename(path: "/tmp/\(String(repeating: "a", count: 129))") == nil)
    }

    @Test func relativePathRejectsAbsoluteAndParentComponents() {
        #expect(RelativePath("Library/Logs/chet") != nil)
        #expect(RelativePath("/Library/Logs") == nil)
        #expect(RelativePath("Library/../Secrets") == nil)
        #expect(RelativePath("..") == nil)
        #expect(RelativePath("") == nil)
    }

    @Test func fieldEncodesNestedCaseValueWithSortedKeys() throws {
        let path = try #require(RelativePath("a/b/c"))
        let field = try #require(LogField.path(.relativePath, path))
        #expect(
            try encoded(field)
                == #"{"key":"relativePath","value":{"path":"a/b/c"}}"#)
    }

    @Test func fieldEncodesRedactionAndCounts() throws {
        #expect(
            try encoded(LogField.redacted(.view, .userName))
                == #"{"key":"view","value":{"redacted":"userName"}}"#)
        #expect(
            try encoded(LogField.count(.items, 7))
                == #"{"key":"items","value":{"count":7}}"#)
        #expect(
            try encoded(LogField.code(.step, .stepScan))
                == #"{"key":"step","value":{"status":1}}"#)
    }

    @Test func optionalFieldFactoriesRejectNil() {
        #expect(LogField.basename(.item, nil) == nil)
        #expect(LogField.path(.relativePath, nil) == nil)
        #expect(LogField.basename(.item, Basename("example.txt")) != nil)
    }
}
