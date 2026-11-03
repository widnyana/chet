import Foundation

public struct PhotoInfo: Sendable {
    public let entry: WalkEntry
    public let pixels: Int
    public let features: PerceptualHash.Features
}

public struct PhotoCluster: Sendable {
    /// Largest image (then oldest) stays.
    public let keeper: PhotoInfo
    public let others: [PhotoInfo]
    public var reclaimableBytes: Int64 { others.reduce(0) { $0 + $1.entry.reclaimableBytes } }
}

public struct PhotoScanResult: Sendable {
    public let clusters: [PhotoCluster]
    public let blurry: [PhotoInfo]
}

/// Near-duplicate and blurry photos. Hashing and pair matching run on the GPU when available.
public struct SimilarPhotos: Sendable {
    public static let extensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp",
    ]

    public let policy: SafetyPolicy
    public var maxDistance = 10
    /// Laplacian variance below this counts as blurry. Tune on real photo sets.
    public var blurThreshold = 60.0
    public var useGPU = true
    /// Images per GPU command buffer. Small, so one submission stays well under 50 ms.
    public var batchSize = 32

    public init(policy: SafetyPolicy) {
        self.policy = policy
    }

    public func scan(_ roots: [URL]) throws -> PhotoScanResult {
        var entries: [WalkEntry] = []
        let walker = FileWalker(policy: policy)
        for root in roots {
            try walker.walk(root) { entry in
                if Self.extensions.contains(entry.url.pathExtension.lowercased()) { entries.append(entry) }
            }
        }
        let gpu = useGPU ? GPUContext.shared : nil
        var photos: [PhotoInfo] = []
        for start in stride(from: 0, to: entries.count, by: batchSize) {
            try Task.checkCancellation()
            // ponytail: decodes sequentially; use DispatchQueue.concurrentPerform if decoding dominates.
            var decoded: [(WalkEntry, [UInt8], Int)] = []
            for entry in entries[start..<min(start + batchSize, entries.count)] {
                if let image = PerceptualHash.bitmap(entry.url) { decoded.append((entry, image.rgba, image.pixels)) }
            }
            let features =
                try gpu.map { try PerceptualHash.gpu(decoded.map(\.1), context: $0) }
                ?? decoded.map { PerceptualHash.cpu($0.1) }
            for (item, feature) in zip(decoded, features) {
                photos.append(PhotoInfo(entry: item.0, pixels: item.2, features: feature))
            }
        }

        let hashes = photos.map(\.features.hash)
        let pairs =
            try gpu.map { try PerceptualHash.gpuPairs(hashes, maxDistance: maxDistance, context: $0) }
            ?? PerceptualHash.cpuPairs(hashes, maxDistance: maxDistance)
        var parent = Array(photos.indices)
        func root(_ i: Int) -> Int {
            var i = i
            while parent[i] != i {
                parent[i] = parent[parent[i]]
                i = parent[i]
            }
            return i
        }
        for (a, b) in pairs { parent[root(a)] = root(b) }
        var members: [Int: [PhotoInfo]] = [:]
        for index in photos.indices { members[root(index), default: []].append(photos[index]) }

        let clusters = members.values.filter { $0.count > 1 }.map { group -> PhotoCluster in
            let keeper = group.max {
                ($0.pixels, $1.entry.stamp.modified) < ($1.pixels, $0.entry.stamp.modified)
            }!
            return PhotoCluster(keeper: keeper, others: group.filter { $0.entry.url != keeper.entry.url })
        }
        return PhotoScanResult(
            clusters: clusters.sorted { $0.reclaimableBytes > $1.reclaimableBytes },
            blurry: photos.filter { $0.features.variance < blurThreshold })
    }
}
