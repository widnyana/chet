import AVFoundation
import CoreGraphics
import Foundation

public struct VideoInfo: Sendable {
    public let entry: WalkEntry
    public let duration: Double
    /// Width x height of the video track.
    public let pixels: Int
    public let frameHashes: [UInt64]
}

public struct VideoCluster: Sendable {
    /// Highest resolution (then largest file, then oldest) stays.
    public let keeper: VideoInfo
    public let others: [VideoInfo]
    public var reclaimableBytes: Int64 { others.reduce(0) { $0 + $1.entry.reclaimableBytes } }
}

/// Near-duplicate videos: 5 frames sampled at fixed fractions of the duration, hashed with the
/// photo pHash (GPU when available). Two videos match when durations differ by under 2 % and
/// at least 4 of 5 frame hashes are within `maxDistance` bits.
public struct SimilarVideos: Sendable {
    public static let extensions: Set<String> = ["mov", "mp4", "m4v"]
    static let fractions = [0.1, 0.3, 0.5, 0.7, 0.9]

    public let policy: SafetyPolicy
    public var maxDistance = 10
    public var useGPU = true

    public init(policy: SafetyPolicy) {
        self.policy = policy
    }

    public func scan(_ roots: [URL]) async throws -> [VideoCluster] {
        var entries: [WalkEntry] = []
        let walker = FileWalker(policy: policy)
        for root in roots {
            try walker.walk(root) { entry in
                if Self.extensions.contains(entry.url.pathExtension.lowercased()) { entries.append(entry) }
            }
        }
        let gpu = useGPU ? GPUContext.shared : nil
        var videos: [VideoInfo] = []
        for entry in entries {
            try Task.checkCancellation()
            guard let sampled = await Self.frames(entry.url) else { continue }
            let bitmaps = sampled.images.compactMap(PerceptualHash.bitmap)
            guard bitmaps.count == Self.fractions.count else { continue }
            let features = try gpu.map { try PerceptualHash.gpu(bitmaps, context: $0) } ?? bitmaps.map(PerceptualHash.cpu)
            videos.append(
                VideoInfo(
                    entry: entry, duration: sampled.duration, pixels: sampled.pixels,
                    frameHashes: features.map(\.hash)))
        }

        // ponytail: O(n^2) CPU pair check; videos are few. Move to a GPU kernel if libraries get huge.
        var parent = Array(videos.indices)
        func root(_ i: Int) -> Int {
            var i = i
            while parent[i] != i {
                parent[i] = parent[parent[i]]
                i = parent[i]
            }
            return i
        }
        for i in videos.indices {
            for j in (i + 1)..<videos.count where matches(videos[i], videos[j]) { parent[root(i)] = root(j) }
        }
        var members: [Int: [VideoInfo]] = [:]
        for index in videos.indices { members[root(index), default: []].append(videos[index]) }
        let clusters = members.values.filter { $0.count > 1 }.map { group -> VideoCluster in
            let keeper = group.max {
                ($0.pixels, $0.entry.stamp.size, $1.entry.stamp.modified)
                    < ($1.pixels, $1.entry.stamp.size, $0.entry.stamp.modified)
            }!
            return VideoCluster(keeper: keeper, others: group.filter { $0.entry.url != keeper.entry.url })
        }
        return clusters.sorted { $0.reclaimableBytes > $1.reclaimableBytes }
    }

    func matches(_ a: VideoInfo, _ b: VideoInfo) -> Bool {
        let longest = max(a.duration, b.duration)
        guard longest > 0, abs(a.duration - b.duration) / longest < 0.02 else { return false }
        let close = zip(a.frameHashes, b.frameHashes).filter { PerceptualHash.hamming($0, $1) <= maxDistance }.count
        return close >= 4
    }

    /// Duration in seconds and one frame per sample fraction. Nil when the file is not a readable video.
    static func frames(_ url: URL) async -> (duration: Double, pixels: Int, images: [CGImage])? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration).seconds, duration.isFinite, duration > 0,
            let track = try? await asset.loadTracks(withMediaType: .video).first,
            let size = try? await track.load(.naturalSize)
        else {
            return nil
        }
        let pixels = Int(abs(size.width * size.height))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: PerceptualHash.side, height: PerceptualHash.side)
        var images: [CGImage] = []
        for fraction in fractions {
            let time = CMTime(seconds: duration * fraction, preferredTimescale: 600)
            guard let frame = try? await generator.image(at: time) else { return nil }
            images.append(frame.image)
        }
        return (duration, pixels, images)
    }
}
