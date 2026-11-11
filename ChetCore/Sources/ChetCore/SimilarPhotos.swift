import Foundation
import Metal

public struct PhotoInfo: Sendable {
    public let entry: WalkEntry
    public let width: Int
    public let height: Int
    public let features: PerceptualHash.Features
    public var pixels: Int { width * height }
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

/// Near-duplicate and blurry photos. Hashing runs on the GPU when available.
public struct SimilarPhotos: Sendable {
    public static let extensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp",
    ]

    public let policy: SafetyPolicy
    public var maxDistance = 6
    /// Laplacian variance below this counts as blurry. Tune on real photo sets.
    public var blurThreshold = 60.0
    public var useGPU = true
    /// Images per GPU command buffer. Small, so one submission stays well under 50 ms.
    public var batchSize = 64

    public init(policy: SafetyPolicy) {
        self.policy = policy
    }

    public func scan(_ roots: [URL]) throws -> PhotoScanResult {
        var entries: [WalkEntry] = []
        let walker = FileWalker(policy: policy)
        for root in roots {
            try walker.walk(root) { entries.append($0) }
        }
        return try scan(entries: entries)
    }

    /// One decoded image ready for hashing.
    private struct Row: Sendable {
        let entry: WalkEntry
        let size: PerceptualHash.Decoded
    }

    /// Raw pointers handed to the decode workers. Each worker writes disjoint slots, so no
    /// lock is needed.
    private struct DecodeTargets: @unchecked Sendable {
        let bitmap: UnsafeMutableRawPointer
        let slots: UnsafeMutablePointer<Row?>
    }

    /// Decodes a batch on `workers` threads straight into the shared buffer, so the CPU never
    /// copies a bitmap into Metal. Undecodable rows are dropped and the survivors compacted.
    private func decode(
        _ entries: [WalkEntry], _ start: Int, _ count: Int, into input: MTLBuffer,
        _ imageBytes: Int, _ workers: Int
    ) -> [Row] {
        let base = input.contents()
        var slots = [Row?](repeating: nil, count: count)
        slots.withUnsafeMutableBufferPointer { buffer in
            guard let output = buffer.baseAddress else { return }
            let targets = DecodeTargets(bitmap: base, slots: output)
            let stride = min(workers, count)
            DispatchQueue.concurrentPerform(iterations: stride) { worker in
                var index = worker
                while index < count {
                    let entry = entries[start + index]
                    if let size = PerceptualHash.bitmap(
                        entry.url, into: targets.bitmap.advanced(by: index * imageBytes))
                    {
                        targets.slots[index] = Row(entry: entry, size: size)
                    }
                    index += stride
                }
            }
        }
        var compact: [Row] = []
        compact.reserveCapacity(count)
        for index in 0..<count {
            guard let slot = slots[index] else { continue }
            if compact.count != index {
                memcpy(
                    base.advanced(by: compact.count * imageBytes),
                    base.advanced(by: index * imageBytes), imageBytes)
            }
            compact.append(slot)
        }
        return compact
    }

    private func photo(_ row: Row, _ features: PerceptualHash.Features) -> PhotoInfo {
        PhotoInfo(entry: row.entry, width: row.size.width, height: row.size.height, features: features)
    }

    /// Finds similar and blurry photos among files that were already walked (non-images are ignored).
    public func scan(entries all: [WalkEntry]) throws -> PhotoScanResult {
        let entries = all.filter { Self.extensions.contains($0.url.pathExtension.lowercased()) }
        let gpu = useGPU ? GPUContext.shared : nil
        // One buffer set for the whole scan; per-batch buffers stay in Metal's pool.
        let buffers = gpu.flatMap { try? PerceptualHash.makeBatchBuffers(capacity: batchSize, context: $0) }
        let workers = min(6, max(1, ProcessInfo.processInfo.activeProcessorCount))
        let imageBytes = PerceptualHash.side * PerceptualHash.side * 4
        var photos: [PhotoInfo] = []
        for start in stride(from: 0, to: entries.count, by: batchSize) {
            try Task.checkCancellation()
            // Every eighth batch, plus once after the loop: decode slabs are large and the
            // allocator keeps them until asked.
            if (start / batchSize) % 8 == 7 { PerceptualHash.releaseFreePages() }
            let count = min(batchSize, entries.count - start)
            let features: [PerceptualHash.Features]
            if let gpu, let buffers {
                // Decode on a few workers straight into the shared buffer, then hash the batch
                // with one threadgroup per image. No CPU bitmap copy per image.
                let decoded = decode(entries, start, count, into: buffers.input, imageBytes, workers)
                if let computed = try? PerceptualHash.features(count: decoded.count, buffers: buffers, context: gpu) {
                    features = computed
                } else {
                    let base = buffers.input.contents()
                    features = (0..<decoded.count).map { index in
                        PerceptualHash.cpu(
                            Array(
                                UnsafeRawBufferPointer(
                                    start: base.advanced(by: index * imageBytes), count: imageBytes)))
                    }
                }
                for (item, feature) in zip(decoded, features) {
                    photos.append(photo(item, feature))
                }
                continue
            }
            // No GPU: decode into arrays and hash on the CPU.
            var rgba: [(Row, [UInt8])] = []
            rgba.reserveCapacity(count)
            for index in 0..<count {
                guard let image = PerceptualHash.bitmap(entries[start + index].url) else { continue }
                rgba.append((Row(entry: entries[start + index], size: image.size), image.rgba))
            }
            features = rgba.map { PerceptualHash.cpu($0.1) }
            for (item, feature) in zip(rgba.map(\.0), features) {
                photos.append(photo(item, feature))
            }
        }

        PerceptualHash.releaseFreePages()

        return PhotoScanResult(
            clusters: Self.clusters(photos, maxDistance: maxDistance),
            blurry: photos.filter { $0.features.variance < blurThreshold })
    }

    static func leaderGroups(_ photos: [PhotoInfo], maxDistance: Int) -> [[PhotoInfo]] {
        let order = photos.indices.sorted { lhs, rhs in
            if photos[lhs].pixels != photos[rhs].pixels {
                return photos[lhs].pixels > photos[rhs].pixels
            }
            return photos[lhs].entry.stamp.modified > photos[rhs].entry.stamp.modified
        }
        var claimed = [Bool](repeating: false, count: photos.count)
        var groups: [[PhotoInfo]] = []
        for index in order {
            guard !claimed[index], hasInformation(photos[index]) else { continue }
            let leader = photos[index]
            var group = [leader]
            for candidateIndex in order where candidateIndex != index && !claimed[candidateIndex] {
                let candidate = photos[candidateIndex]
                guard hasInformation(candidate), shapeMatches(leader, candidate) else { continue }
                guard
                    group.allSatisfy({
                        PerceptualHash.hamming($0.features.hash, candidate.features.hash) <= maxDistance
                    })
                else { continue }
                group.append(candidate)
                claimed[candidateIndex] = true
            }
            claimed[index] = true
            groups.append(group)
        }
        return groups
    }

    static func clusters(_ photos: [PhotoInfo], maxDistance: Int) -> [PhotoCluster] {
        let clusters = leaderGroups(photos, maxDistance: maxDistance).filter { $0.count > 1 }.map {
            group -> PhotoCluster in
            let keeper = group.max {
                ($0.pixels, $1.entry.stamp.modified) < ($1.pixels, $0.entry.stamp.modified)
            }!
            return PhotoCluster(keeper: keeper, others: group.filter { $0.entry.url != keeper.entry.url })
        }
        return clusters.sorted { $0.reclaimableBytes > $1.reclaimableBytes }
    }

    private static func hasInformation(_ photo: PhotoInfo) -> Bool {
        photo.features.hash.nonzeroBitCount >= 8 && photo.features.variance >= 4.0
    }

    private static func shapeMatches(_ leader: PhotoInfo, _ candidate: PhotoInfo) -> Bool {
        guard leader.height > 0, candidate.height > 0 else { return false }
        let leaderRatio = Double(leader.width) / Double(leader.height)
        let candidateRatio = Double(candidate.width) / Double(candidate.height)
        if abs(leaderRatio - candidateRatio) <= 0.05 * max(leaderRatio, candidateRatio) { return true }
        let leaderPixels = Double(leader.pixels)
        let candidatePixels = Double(candidate.pixels)
        return abs(leaderPixels - candidatePixels) <= 0.10 * max(leaderPixels, candidatePixels)
    }
}
