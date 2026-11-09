import Foundation
import Testing

@testable import ChetCore

struct GPUHasherTests {
    private func noise(_ count: Int, seed: UInt64) -> Data {
        var state = seed
        var data = Data(count: count)
        for i in 0..<count {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            data[i] = UInt8(truncatingIfNeeded: state >> 33)
        }
        return data
    }

    @Test(arguments: [0, 1, 65_535, 65_536, 65_537, 10_000_000])
    func gpuDigestMatchesCPUReference(size: Int) throws {
        let dir = try TempDir()
        let data = noise(size, seed: UInt64(size) + 1)
        let url = dir.url.appendingPathComponent("f")
        try data.write(to: url)
        let gpu = GPUHasher(context: try GPUContext())
        #expect(try gpu.digest(url) == GPUHasher.cpuDigest(data))
    }

    @Test func chunkBoundariesDoNotChangeDigest() throws {
        let dir = try TempDir()
        let data = noise(1_000_000, seed: 9)
        let url = dir.url.appendingPathComponent("f")
        try data.write(to: url)
        var small = GPUHasher(context: try GPUContext())
        small.chunkBytes = 2 * 65_536
        #expect(try small.digest(url) == GPUHasher.cpuDigest(data))
    }

    @Test func digestReusesOneScratchSet() throws {
        let dir = try TempDir()
        let url = dir.url.appendingPathComponent("f")
        try noise(200_000, seed: 5).write(to: url)
        let gpu = GPUHasher(context: try GPUContext())
        #expect(gpu.scratchIdentity == nil)
        _ = try gpu.digest(url)
        let first = try #require(gpu.scratchIdentity)
        let bytes = try #require(gpu.scratchBytes)
        _ = try gpu.digest(url)
        #expect(gpu.scratchIdentity == first)
        #expect(gpu.scratchBytes == bytes)
        var small = gpu
        small.chunkBytes = 2 * 65_536
        _ = try small.digest(url)
        #expect(gpu.scratchIdentity != first)
    }

    @Test func swappingBlocksChangesDigest() {
        let first = noise(65_536, seed: 1)
        let second = noise(65_536, seed: 2)
        #expect(GPUHasher.cpuDigest(first + second) != GPUHasher.cpuDigest(second + first))
    }

    @Test func gpuStrategyFindsDuplicates() throws {
        let dir = try TempDir()
        let data = noise(2_000_000, seed: 3)
        for folder in ["a", "b", "c"] {
            let url = dir.url.appendingPathComponent("\(folder)/x")
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        var different = data
        different[1_000_000] ^= 0xFF
        try different.write(to: dir.url.appendingPathComponent("d"))
        var finder = DuplicateFinder(policy: dir.policy)
        finder.hasher = .gpu
        let groups = try finder.find(in: [dir.url])
        #expect(groups.count == 1)
        #expect(groups.first?.duplicates.count == 2)
    }

    @Test func forcedHashCollisionIsRejectedByByteCompare() throws {
        let dir = try TempDir()
        var data = Data(repeating: 7, count: 2_000_000)
        try data.write(to: dir.url.appendingPathComponent("a"))
        data[1_000_000] = 9
        try data.write(to: dir.url.appendingPathComponent("b"))
        var finder = DuplicateFinder(policy: dir.policy)
        finder.fullHashOverride = { _ in "same" }
        #expect(try finder.find(in: [dir.url]).isEmpty)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CHET_BENCH"] != nil))
    func hashingBenchmark() throws {
        let dir = try TempDir()
        var urls: [URL] = []
        for i in 0..<4 {
            let url = dir.url.appendingPathComponent("bench\(i)")
            try noise(1 << 20, seed: UInt64(i)).write(to: url)
            let handle = try FileHandle(forWritingTo: url)
            for _ in 1..<256 { try handle.write(contentsOf: noise(1 << 20, seed: UInt64(i))) }
            try handle.close()
            urls.append(url)
        }
        let gpu = GPUHasher(context: try GPUContext())
        let megabytes = Double(urls.count * 256)
        var start = Date()
        for url in urls { _ = try gpu.digest(url) }
        let gpuRate = megabytes / Date().timeIntervalSince(start)
        start = Date()
        for url in urls { _ = try DuplicateFinder.fullHash(url) }
        let shaRate = megabytes / Date().timeIntervalSince(start)
        print("hashing benchmark: gpu \(Int(gpuRate)) MB/s, sha256 \(Int(shaRate)) MB/s")
    }
}
