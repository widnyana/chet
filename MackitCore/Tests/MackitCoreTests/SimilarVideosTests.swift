import Foundation
import Testing

@testable import MackitCore

struct SimilarVideosTests {
    @Test func reencodedCopyMatches() async throws {
        let dir = try TempDir()
        try await VideoFixtures.write(to: dir.url.appendingPathComponent("clips/a.mov"), base: 1, seconds: 3)
        try await VideoFixtures.write(
            to: dir.url.appendingPathComponent("clips/b.mov"), base: 1, seconds: 3, size: 160, bitRate: 200_000)
        let clusters = try await SimilarVideos(policy: dir.policy).scan([dir.url])
        #expect(clusters.count == 1)
        let cluster = try #require(clusters.first)
        #expect(cluster.keeper.entry.url.lastPathComponent == "a.mov")
        #expect(cluster.others.map(\.entry.url.lastPathComponent) == ["b.mov"])
    }

    @Test func differentVideosDoNotMatch() async throws {
        let dir = try TempDir()
        try await VideoFixtures.write(to: dir.url.appendingPathComponent("a.mov"), base: 1, seconds: 3)
        try await VideoFixtures.write(to: dir.url.appendingPathComponent("b.mov"), base: 50, seconds: 3)
        #expect(try await SimilarVideos(policy: dir.policy).scan([dir.url]).isEmpty)
    }

    @Test func differentDurationsNeverMatch() async throws {
        let dir = try TempDir()
        try await VideoFixtures.write(to: dir.url.appendingPathComponent("a.mov"), base: 1, seconds: 10, fps: 2)
        try await VideoFixtures.write(to: dir.url.appendingPathComponent("b.mov"), base: 1, seconds: 12, fps: 2)
        #expect(try await SimilarVideos(policy: dir.policy).scan([dir.url]).isEmpty)
    }

    @Test func unreadableVideoIsSkipped() async throws {
        let dir = try TempDir()
        try Data(repeating: 0x42, count: 4096).write(to: dir.url.appendingPathComponent("broken.mov"))
        try await VideoFixtures.write(to: dir.url.appendingPathComponent("good.mov"), base: 1, seconds: 3)
        #expect(await SimilarVideos.frames(dir.url.appendingPathComponent("broken.mov")) == nil)
        #expect(try await SimilarVideos(policy: dir.policy).scan([dir.url]).isEmpty)
    }
}
