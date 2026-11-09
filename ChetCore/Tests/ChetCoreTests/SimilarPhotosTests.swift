import Foundation
import Testing
import UniformTypeIdentifiers

@testable import ChetCore

struct SimilarPhotosTests {
    @Test func gpuMatchesCPUReference() throws {
        let gpu = try GPUContext()
        let dir = try TempDir()
        var bitmaps: [[UInt8]] = []
        for seed in 1...20 {
            let url = PhotoFixtures.write(
                PhotoFixtures.blocks(seed: UInt64(seed)), to: dir.url.appendingPathComponent("\(seed).png"))
            bitmaps.append(try #require(PerceptualHash.bitmap(url)).rgba)
        }
        let fromGPU = try PerceptualHash.gpu(bitmaps, context: gpu)
        #expect(fromGPU == bitmaps.map(PerceptualHash.cpu))
    }

    @Test func reusedBatchBuffersMatchAFreshBatch() throws {
        let gpu = try GPUContext()
        let dir = try TempDir()
        var bitmaps: [[UInt8]] = []
        for seed in 1...5 {
            let url = PhotoFixtures.write(
                PhotoFixtures.blocks(seed: UInt64(seed)), to: dir.url.appendingPathComponent("\(seed).png"))
            bitmaps.append(try #require(PerceptualHash.bitmap(url)).rgba)
        }
        let buffers = try PerceptualHash.makeBatchBuffers(capacity: 8, context: gpu)
        #expect(try PerceptualHash.gpu(bitmaps, buffers: buffers, context: gpu) == bitmaps.map(PerceptualHash.cpu))
        // A shorter second batch must not read rows left over from the first one.
        let half = Array(bitmaps.prefix(2))
        #expect(try PerceptualHash.gpu(half, buffers: buffers, context: gpu) == half.map(PerceptualHash.cpu))
    }

    @Test func gpuPairsMatchCPUPairs() throws {
        let gpu = try GPUContext()
        var state: UInt64 = 42
        let hashes = (0..<50).map { _ -> UInt64 in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
        let cpu = PerceptualHash.cpuPairs(hashes, maxDistance: 28).map { "\($0.0)-\($0.1)" }
        let fromGPU = try PerceptualHash.gpuPairs(hashes, maxDistance: 28, context: gpu).map { "\($0.0)-\($0.1)" }
        #expect(!cpu.isEmpty)
        #expect(Set(fromGPU) == Set(cpu))
        #expect(fromGPU.count == cpu.count)
    }

    @Test func resizedJPEGCopyIsSimilar() throws {
        let dir = try TempDir()
        let image = PhotoFixtures.blocks(seed: 7)
        let original = PhotoFixtures.write(image, to: dir.url.appendingPathComponent("a.png"))
        let copy = PhotoFixtures.write(
            PhotoFixtures.resized(image, to: 256), to: dir.url.appendingPathComponent("b.jpg"), type: .jpeg)
        let a = PerceptualHash.cpu(try #require(PerceptualHash.bitmap(original)).rgba)
        let b = PerceptualHash.cpu(try #require(PerceptualHash.bitmap(copy)).rgba)
        #expect(PerceptualHash.hamming(a.hash, b.hash) <= 10)
    }

    @Test func differentImagesAreFarApart() throws {
        let dir = try TempDir()
        let first = PhotoFixtures.write(PhotoFixtures.blocks(seed: 1), to: dir.url.appendingPathComponent("1.png"))
        let second = PhotoFixtures.write(PhotoFixtures.blocks(seed: 2), to: dir.url.appendingPathComponent("2.png"))
        let a = PerceptualHash.cpu(try #require(PerceptualHash.bitmap(first)).rgba)
        let b = PerceptualHash.cpu(try #require(PerceptualHash.bitmap(second)).rgba)
        #expect(PerceptualHash.hamming(a.hash, b.hash) > 20)
    }

    @Test func blurredCopyHasLowVarianceAndIsFlagged() throws {
        let dir = try TempDir()
        let image = PhotoFixtures.blocks(seed: 3)
        let sharpURL = PhotoFixtures.write(image, to: dir.url.appendingPathComponent("photos/sharp.png"))
        let blurURL = PhotoFixtures.write(
            PhotoFixtures.blurred(image), to: dir.url.appendingPathComponent("photos/blur.png"))
        let sharp = PerceptualHash.cpu(try #require(PerceptualHash.bitmap(sharpURL)).rgba)
        let blur = PerceptualHash.cpu(try #require(PerceptualHash.bitmap(blurURL)).rgba)
        #expect(blur.variance < sharp.variance / 4)
        let result = try SimilarPhotos(policy: dir.policy).scan([dir.url])
        #expect(result.blurry.map(\.entry.url.lastPathComponent) == ["blur.png"])
    }

    @Test func undecodableFileIsSkipped() throws {
        let dir = try TempDir()
        let good = PhotoFixtures.write(
            PhotoFixtures.blocks(seed: 5), to: dir.url.appendingPathComponent("good.jpg"), type: .jpeg)
        let bytes = try Data(contentsOf: good)
        try bytes.prefix(20).write(to: dir.url.appendingPathComponent("broken.jpg"))
        #expect(PerceptualHash.bitmap(dir.url.appendingPathComponent("broken.jpg")) == nil)
        let result = try SimilarPhotos(policy: dir.policy).scan([dir.url])
        #expect(result.clusters.isEmpty)
    }

    @Test func similarPhotosFormOneClusterWithLargestAsKeeper() throws {
        let dir = try TempDir()
        let image = PhotoFixtures.blocks(seed: 9)
        PhotoFixtures.write(image, to: dir.url.appendingPathComponent("trip/original.png"))
        PhotoFixtures.write(
            PhotoFixtures.resized(image, to: 256), to: dir.url.appendingPathComponent("trip/small.jpg"), type: .jpeg)
        PhotoFixtures.write(
            PhotoFixtures.resized(image, to: 384), to: dir.url.appendingPathComponent("trip/medium.jpg"), type: .jpeg)
        PhotoFixtures.write(PhotoFixtures.blocks(seed: 10), to: dir.url.appendingPathComponent("trip/other.png"))
        let result = try SimilarPhotos(policy: dir.policy).scan([dir.url])
        #expect(result.clusters.count == 1)
        let cluster = try #require(result.clusters.first)
        #expect(cluster.keeper.entry.url.lastPathComponent == "original.png")
        #expect(Set(cluster.others.map(\.entry.url.lastPathComponent)) == ["small.jpg", "medium.jpg"])
    }
}
