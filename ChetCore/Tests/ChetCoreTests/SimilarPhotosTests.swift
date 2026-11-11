import CoreGraphics
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

    @Test func sameImageHashesIdenticallyAcrossBatches() throws {
        let gpu = try GPUContext()
        let dir = try TempDir()
        let url = PhotoFixtures.write(
            PhotoFixtures.blocks(seed: 11), to: dir.url.appendingPathComponent("same.png"))
        let first = try #require(PerceptualHash.bitmap(url))
        let second = try #require(PerceptualHash.bitmap(url))
        #expect(first.rgba == second.rgba)
        #expect(first.size == second.size)
        let buffers = try PerceptualHash.makeBatchBuffers(capacity: 1, context: gpu)
        #expect(
            try PerceptualHash.gpu([first.rgba], buffers: buffers, context: gpu) == [PerceptualHash.cpu(first.rgba)])
        #expect(
            try PerceptualHash.gpu([second.rgba], buffers: buffers, context: gpu) == [PerceptualHash.cpu(second.rgba)])
    }

    @Test func transparentPNGHashesLikeTheSameArtOnWhite() throws {
        let dir = try TempDir()
        let art = PhotoFixtures.transparentBlocks(seed: 13)
        let transparent = PhotoFixtures.write(art, to: dir.url.appendingPathComponent("transparent.png"))
        let white = PhotoFixtures.write(
            PhotoFixtures.onBackground(art, CGColor(red: 1, green: 1, blue: 1, alpha: 1)),
            to: dir.url.appendingPathComponent("white.png"))
        let black = PhotoFixtures.write(
            PhotoFixtures.onBackground(art, CGColor(red: 0, green: 0, blue: 0, alpha: 1)),
            to: dir.url.appendingPathComponent("black.png"))
        let cleared = PerceptualHash.cpu(try #require(PerceptualHash.bitmap(transparent)).rgba)
        let onWhite = PerceptualHash.cpu(try #require(PerceptualHash.bitmap(white)).rgba)
        let onBlack = PerceptualHash.cpu(try #require(PerceptualHash.bitmap(black)).rgba)
        #expect(PerceptualHash.hamming(cleared.hash, onWhite.hash) == 0)
        #expect(PerceptualHash.hamming(cleared.hash, onBlack.hash) > 10)
    }

    @Test func aspectRatioSurvivesTheHash() throws {
        let dir = try TempDir()
        let wide = PhotoFixtures.write(
            PhotoFixtures.blocks(seed: 17, width: 512, height: 256),
            to: dir.url.appendingPathComponent("wide.png"))
        let tall = PhotoFixtures.write(
            PhotoFixtures.blocks(seed: 17, width: 256, height: 512),
            to: dir.url.appendingPathComponent("tall.png"))
        let wideImage = try #require(PerceptualHash.bitmap(wide))
        let tallImage = try #require(PerceptualHash.bitmap(tall))
        let side = PerceptualHash.side
        #expect(wideImage.size == PerceptualHash.Decoded(width: 512, height: 256))
        #expect(tallImage.size == PerceptualHash.Decoded(width: 256, height: 512))
        #expect(wideImage.rgba[0..<(side * 4)].allSatisfy { $0 == 255 })
        #expect(wideImage.rgba[(side / 2) * side * 4..<(side / 2 + 1) * side * 4].contains { $0 != 255 })
        let a = PerceptualHash.cpu(wideImage.rgba)
        let b = PerceptualHash.cpu(tallImage.rgba)
        #expect(PerceptualHash.hamming(a.hash, b.hash) > 10)
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

    @Test func chainOfThreeSplitsIntoTwoLeaderGroups() throws {
        let a = photo("a.png", width: 1000, height: 1000, hash: .max, modified: 3)
        let b = photo("b.png", width: 1000, height: 1000, hash: .max ^ 0b1111, modified: 2)
        let c = photo("c.png", width: 1000, height: 1000, hash: .max ^ 0b1111111, modified: 1)
        let groups = SimilarPhotos.leaderGroups([a, b, c], maxDistance: 6)
        #expect(groups.count == 2)
        let first = try #require(groups.first)
        #expect(first.map(\.entry.url.lastPathComponent) == ["a.png", "b.png"])
        #expect(groups.last?.map(\.entry.url.lastPathComponent) == ["c.png"])
        #expect(PerceptualHash.hamming(a.features.hash, c.features.hash) > 6)
    }

    @Test func everyClusterMemberIsWithinTheDiameterOfTheLeaderAndEachOther() throws {
        let leader = photo("leader.png", width: 1000, height: 1000, hash: .max, modified: 3)
        let second = photo("second.png", width: 1000, height: 1000, hash: .max ^ 0b111, modified: 2)
        let third = photo("third.png", width: 1000, height: 1000, hash: .max ^ 0b111000, modified: 1)
        let cluster = try #require(SimilarPhotos.clusters([leader, second, third], maxDistance: 6).first)
        let members = [cluster.keeper] + cluster.others
        #expect(members.count == 3)
        for member in members {
            for other in members where member.entry.url != other.entry.url {
                #expect(PerceptualHash.hamming(member.features.hash, other.features.hash) <= 6)
            }
        }
    }

    @Test func flatImagesNeverGroup() {
        let flat = (0..<10).map {
            photo("flat\($0).png", width: 1000, height: 1000, hash: 0, variance: 0, modified: Double($0))
        }
        #expect(SimilarPhotos.leaderGroups(flat, maxDistance: 6).isEmpty)
        #expect(SimilarPhotos.clusters(flat, maxDistance: 6).isEmpty)
    }

    @Test func portraitAndLandscapeOfTheSameContentDoNotGroup() throws {
        let dir = try TempDir()
        PhotoFixtures.write(
            PhotoFixtures.blocks(seed: 17, width: 512, height: 256),
            to: dir.url.appendingPathComponent("wide.png"))
        PhotoFixtures.write(
            PhotoFixtures.blocks(seed: 17, width: 256, height: 512),
            to: dir.url.appendingPathComponent("tall.png"))
        let result = try SimilarPhotos(policy: dir.policy).scan([dir.url])
        #expect(result.clusters.isEmpty)
    }

    @Test func resizedCopyWithinTenPercentPixelsIsAdmitted() throws {
        let original = photo("original.png", width: 1200, height: 850, hash: .max, modified: 2)
        let copy = photo("copy.png", width: 1000, height: 1000, hash: .max ^ 0b11, modified: 1)
        let cluster = try #require(SimilarPhotos.clusters([original, copy], maxDistance: 6).first)
        #expect(cluster.keeper.entry.url.lastPathComponent == "original.png")
        #expect(cluster.others.map(\.entry.url.lastPathComponent) == ["copy.png"])
    }

    private func photo(
        _ name: String, width: Int, height: Int, hash: UInt64, variance: Double = 100,
        modified: Double = 0
    ) -> PhotoInfo {
        let samples = Int64((PerceptualHash.side - 2) * (PerceptualHash.side - 2))
        return PhotoInfo(
            entry: WalkEntry(
                url: URL(fileURLWithPath: "/fixtures/\(name)"),
                stamp: FileStamp(
                    inode: 0, size: 1, modified: Date(timeIntervalSince1970: modified), links: 1,
                    isSymlink: false, isRegularFile: true, isDataless: false),
                reclaimableBytes: 1),
            width: width, height: height,
            features: PerceptualHash.Features(
                hash: hash, lapSum: 0, lapSquares: Int64(variance * Double(samples))))
    }
}
