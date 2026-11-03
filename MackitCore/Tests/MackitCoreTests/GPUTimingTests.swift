import Foundation
import Metal
import Testing

@testable import MackitCore

/// GPU submissions must stay short: the GPU is shared with WindowServer.
@Suite(.serialized)
struct GPUTimingTests {
    private func randomHashes(_ count: Int, seed: UInt64) -> [UInt64] {
        var state = seed
        return (0..<count).map { _ in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
    }

    @Test func timingIsRecordedAndResets() throws {
        let gpu = try GPUContext()
        let a = [Float](repeating: 1, count: 1024)
        let bytes = a.count * MemoryLayout<Float>.stride
        let bufA = try #require(gpu.device.makeBuffer(bytes: a, length: bytes, options: .storageModeShared))
        let out = try #require(gpu.device.makeBuffer(length: bytes, options: .storageModeShared))
        try gpu.run("add_arrays", grid: MTLSize(width: a.count, height: 1, depth: 1)) { encoder in
            encoder.setBuffer(bufA, offset: 0, index: 0)
            encoder.setBuffer(bufA, offset: 0, index: 1)
            encoder.setBuffer(out, offset: 0, index: 2)
        }
        #expect(gpu.lastGPUSeconds > 0)
        #expect(gpu.maxGPUSeconds >= gpu.lastGPUSeconds)
        gpu.resetGPUTiming()
        #expect(gpu.maxGPUSeconds == 0)
    }

    @Test func tiledPairsMatchCPUAcrossTileEdges() throws {
        let gpu = try GPUContext()
        let hashes = randomHashes(5_000, seed: 7)
        let cpu = Set(PerceptualHash.cpuPairs(hashes, maxDistance: 22).map { "\($0.0)-\($0.1)" })
        let fromGPU = try PerceptualHash.gpuPairs(hashes, maxDistance: 22, context: gpu)
        #expect(!cpu.isEmpty)
        #expect(Set(fromGPU.map { "\($0.0)-\($0.1)" }) == cpu)
        #expect(fromGPU.count == cpu.count)
    }

    @Test func pairSearchCommandBuffersStayShort() throws {
        let gpu = try GPUContext()
        gpu.resetGPUTiming()
        _ = try PerceptualHash.gpuPairs(randomHashes(5_000, seed: 3), maxDistance: 10, context: gpu)
        #expect(gpu.maxGPUSeconds < 0.05)
    }

    @Test func photoFeatureBatchStaysShort() throws {
        let gpu = try GPUContext()
        let batch = try (0..<SimilarPhotos(policy: SafetyPolicy()).batchSize).map { seed in
            try #require(PerceptualHash.bitmap(PhotoFixtures.blocks(seed: UInt64(seed))))
        }
        gpu.resetGPUTiming()
        _ = try PerceptualHash.gpu(batch, context: gpu)
        #expect(gpu.maxGPUSeconds < 0.05)
    }
}
