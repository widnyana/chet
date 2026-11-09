import Foundation
import Metal

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
    private struct Decoded: Sendable {
        let entry: WalkEntry
        let pixels: Int
    }

    /// Decodes a batch on `workers` threads straight into the shared buffer, so the CPU never
    /// copies a bitmap into Metal. Undecodable rows are dropped and the survivors compacted.
    private func decode(
        _ entries: [WalkEntry], _ start: Int, _ count: Int, into input: MTLBuffer,
        _ imageBytes: Int, _ workers: Int
    ) -> [Decoded] {
        let base = input.contents()
        var slots = [Decoded?](repeating: nil, count: count)
        slots.withUnsafeMutableBufferPointer { buffer in
            nonisolated(unsafe) let output = buffer.baseAddress
            guard let output else { return }
            let stride = min(workers, count)
            DispatchQueue.concurrentPerform(iterations: stride) { worker in
                var index = worker
                while index < count {
                    let entry = entries[start + index]
                    if let pixels = PerceptualHash.bitmap(
                        entry.url, into: base.advanced(by: index * imageBytes))
                    {
                        output[index] = Decoded(entry: entry, pixels: pixels)
                    }
                    index += stride
                }
            }
        }
        var compact: [Decoded] = []
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
                    photos.append(PhotoInfo(entry: item.entry, pixels: item.pixels, features: feature))
                }
                continue
            }
            // No GPU: decode into arrays and hash on the CPU.
            var rgba: [(Decoded, [UInt8])] = []
            rgba.reserveCapacity(count)
            for index in 0..<count {
                guard let image = PerceptualHash.bitmap(entries[start + index].url) else { continue }
                rgba.append((Decoded(entry: entries[start + index], pixels: image.pixels), image.rgba))
            }
            features = rgba.map { PerceptualHash.cpu($0.1) }
            for (item, feature) in zip(rgba.map(\.0), features) {
                photos.append(PhotoInfo(entry: item.entry, pixels: item.pixels, features: feature))
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
