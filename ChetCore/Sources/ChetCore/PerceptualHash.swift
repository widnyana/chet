import CoreGraphics
import Darwin
import Foundation
import ImageIO
import Metal

/// Integer perceptual hash and blur score. `gpu` (Metal) and `cpu` (reference) give identical results.
public enum PerceptualHash {
    public static let side = 256

    public struct Features: Equatable, Sendable {
        public let hash: UInt64
        public let lapSum: Int64
        public let lapSquares: Int64

        /// Laplacian variance. Low means blurry.
        public var variance: Double {
            let n = Double((side - 2) * (side - 2))
            let mean = Double(lapSum) / n
            return Double(lapSquares) / n - mean * mean
        }
    }

    /// Original pixel size of a decoded image.
    public struct Decoded: Equatable, Sendable {
        public let width: Int
        public let height: Int

        public init(width: Int, height: Int) {
            self.width = width
            self.height = height
        }
    }

    /// Opaque white. Every bitmap is cleared to it before drawing, so a flat image hashed on white
    /// equals a transparent export of the same artwork on white.
    static let background: UInt8 = 255

    /// cos((2x + 1) u pi / 64) * 1024, rounded, for u in 0..<8 and x in 0..<32 (index u * 32 + x).
    static let cosTable: [Int32] = (0..<8).flatMap { u in
        (0..<32).map { x in Int32((cos(Double((2 * x + 1) * u) * .pi / 64) * 1024).rounded()) }
    }

    /// Decodes an image file into a side x side RGBA bitmap: the image is aspect-fit and centred
    /// on white. Also returns the original pixel size.
    /// Nil when the file is not a decodable image.
    public static func bitmap(_ url: URL) -> (rgba: [UInt8], size: Decoded)? {
        var rgba = [UInt8](repeating: 0, count: side * side * 4)
        let size = rgba.withUnsafeMutableBytes { buffer in
            bitmap(url, into: buffer.baseAddress!)
        }
        guard let size else { return nil }
        return (rgba, size)
    }

    /// Decodes into caller memory of `side * side * 4` bytes and returns the original pixel size.
    /// Callers hand this a Metal buffer, so a bitmap is never copied after decoding.
    public static func bitmap(_ url: URL, into rgba: UnsafeMutableRawPointer) -> Decoded? {
        // ImageIO keeps its decoded buffers and file data in the caller's autorelease pool. One
        // pool per image releases them now instead of at the end of the whole photo step.
        autoreleasepool {
            let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions),
                let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                let width = properties[kCGImagePropertyPixelWidth] as? Int,
                let height = properties[kCGImagePropertyPixelHeight] as? Int
            else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: side,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
                bitmap(thumbnail, into: rgba)
            else { return nil }
            return Decoded(width: width, height: height)
        }
    }

    /// sRGB once: a color space per image is a per-image allocation with no benefit.
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)

    /// Draws an image into a side x side RGBA bitmap: aspect-fit, centred on white.
    public static func bitmap(_ image: CGImage) -> [UInt8]? {
        var rgba = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = rgba.withUnsafeMutableBytes { buffer in
            bitmap(image, into: buffer.baseAddress!)
        }
        return drawn ? rgba : nil
    }

    /// Draws an image into caller memory of `side * side * 4` bytes: aspect-fit, centred on white.
    public static func bitmap(_ image: CGImage, into rgba: UnsafeMutableRawPointer) -> Bool {
        guard let space = sRGB,
            let context = CGContext(
                data: rgba, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        memset(rgba, Int32(background), side * side * 4)
        context.interpolationQuality = .high
        let box = CGFloat(side)
        let scale = min(box / CGFloat(image.width), box / CGFloat(image.height))
        let fitted = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        context.draw(
            image,
            in: CGRect(
                x: (box - fitted.width) / 2, y: (box - fitted.height) / 2, width: fitted.width,
                height: fitted.height))
        return true
    }

    public static func cpu(_ rgba: [UInt8]) -> Features {
        func gray(_ x: Int, _ y: Int) -> Int {
            let p = (y * side + x) * 4
            return (77 * Int(rgba[p]) + 150 * Int(rgba[p + 1]) + 29 * Int(rgba[p + 2])) >> 8
        }
        var small = [Int](repeating: 0, count: 32 * 32)
        for by in 0..<32 {
            for bx in 0..<32 {
                var sum = 0
                for y in 0..<8 { for x in 0..<8 { sum += gray(bx * 8 + x, by * 8 + y) } }
                small[by * 32 + bx] = sum / 64
            }
        }
        var rows = [Int](repeating: 0, count: 32 * 8)
        for y in 0..<32 {
            for u in 0..<8 {
                var acc = 0
                for x in 0..<32 { acc += small[y * 32 + x] * Int(cosTable[u * 32 + x]) }
                rows[y * 8 + u] = acc
            }
        }
        var coef = [Int64](repeating: 0, count: 64)
        for v in 0..<8 {
            for u in 0..<8 {
                var acc: Int64 = 0
                for y in 0..<32 { acc += Int64(rows[y * 8 + u]) * Int64(cosTable[v * 32 + y]) }
                coef[v * 8 + u] = acc
            }
        }
        let sorted = coef.sorted()
        let median2 = sorted[31] + sorted[32]
        var hash: UInt64 = 0
        for i in 0..<64 where 2 * coef[i] > median2 { hash |= 1 << UInt64(i) }

        var sum: Int64 = 0
        var squares: Int64 = 0
        for y in 1..<(side - 1) {
            for x in 1..<(side - 1) {
                let l = Int64(4 * gray(x, y) - gray(x, y - 1) - gray(x, y + 1) - gray(x - 1, y) - gray(x + 1, y))
                sum += l
                squares += l * l
            }
        }
        return Features(hash: hash, lapSum: sum, lapSquares: squares)
    }

    /// Metal buffers for one photo batch. Allocate once per scan: a fresh set per batch stays
    /// in Metal's pool, so footprint grew with the number of images hashed.
    public struct BatchBuffers: @unchecked Sendable {
        let input: MTLBuffer
        let table: MTLBuffer
        let hashes: MTLBuffer
        let lap: MTLBuffer
        let capacity: Int
    }

    public static func makeBatchBuffers(capacity: Int, context: GPUContext) throws -> BatchBuffers {
        let tableBytes = cosTable.count * MemoryLayout<Int32>.stride
        guard capacity > 0,
            let table = context.device.makeBuffer(bytes: cosTable, length: tableBytes, options: .storageModeShared),
            let input = context.device.makeBuffer(
                length: capacity * side * side * 4, options: .storageModeShared),
            let hashes = context.device.makeBuffer(length: capacity * 8, options: .storageModeShared),
            let lap = context.device.makeBuffer(length: capacity * 16, options: .storageModeShared)
        else { throw GPUError.commandFailed("photo buffers") }
        return BatchBuffers(input: input, table: table, hashes: hashes, lap: lap, capacity: capacity)
    }

    /// Threads per image in `photo_features`. Must match PHOTO_THREADS in Image.metal.
    static let photoThreads = 256

    public static func gpu(_ batch: [[UInt8]], context: GPUContext) throws -> [Features] {
        try gpu(batch, buffers: makeBatchBuffers(capacity: batch.count, context: context), context: context)
    }

    /// Copies CPU bitmaps into the batch buffer, then hashes them. The scan skips the copy by
    /// decoding straight into `buffers.input` and calling `features(count:buffers:context:)`.
    public static func gpu(
        _ batch: [[UInt8]], buffers: BatchBuffers, context: GPUContext
    ) throws -> [Features] {
        let imageBytes = side * side * 4
        for (index, rgba) in batch.enumerated() {
            rgba.withUnsafeBytes { bytes in
                buffers.input.contents().advanced(by: index * imageBytes)
                    .copyMemory(from: bytes.baseAddress!, byteCount: imageBytes)
            }
        }
        return try features(count: batch.count, buffers: buffers, context: context)
    }

    /// Hashes a batch whose bitmaps already sit in `buffers.input`, one threadgroup per image.
    public static func features(
        count: Int, buffers: BatchBuffers, context: GPUContext
    ) throws -> [Features] {
        guard count > 0 else { return [] }
        precondition(count <= buffers.capacity, "photo batch over the buffer capacity")
        try context.run(
            "photo_features", threadgroups: MTLSize(width: count, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: photoThreads, height: 1, depth: 1)
        ) { encoder in
            encoder.setBuffer(buffers.input, offset: 0, index: 0)
            encoder.setBuffer(buffers.table, offset: 0, index: 1)
            encoder.setBuffer(buffers.hashes, offset: 0, index: 2)
            encoder.setBuffer(buffers.lap, offset: 0, index: 3)
        }
        let hashValues = buffers.hashes.contents().bindMemory(to: UInt64.self, capacity: count)
        let lapValues = buffers.lap.contents().bindMemory(to: Int64.self, capacity: count * 2)
        return (0..<count).map {
            Features(hash: hashValues[$0], lapSum: lapValues[$0 * 2], lapSquares: lapValues[$0 * 2 + 1])
        }
    }

    public static func hamming(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }

    /// Hands the allocator back the pages the decoders freed. ImageIO allocates full-size
    /// decode slabs per image; without this they stay resident until the process exits.
    @discardableResult
    public static func releaseFreePages() -> Int {
        Int(malloc_zone_pressure_relief(nil, 0))
    }

    public static func cpuPairs(_ hashes: [UInt64], maxDistance: Int) -> [(Int, Int)] {
        var pairs: [(Int, Int)] = []
        for i in hashes.indices {
            for j in (i + 1)..<hashes.count where hamming(hashes[i], hashes[j]) <= maxDistance { pairs.append((i, j)) }
        }
        return pairs
    }

    /// Largest side of one pair-search tile: 2048 x 2048 threads per command buffer.
    static let pairTile = 2048

    /// Pairs within `maxDistance`, one thread per candidate cell, one command buffer per tile so a
    /// submission stays short. Each tile fills the pair buffer from zero and is drained before the
    /// next tile, so the result is bounded by the library instead of one fixed buffer. A tile can
    /// report at most half of its cells, which is the buffer size.
    public static func gpuPairs(
        _ hashes: [UInt64], maxDistance: Int, context: GPUContext
    ) throws -> [(Int, Int)] {
        let count = hashes.count
        guard count > 1 else { return [] }
        let tileCapacity = pairTile * pairTile / 2
        guard
            let hashBuffer = context.device.makeBuffer(
                bytes: hashes, length: count * 8, options: .storageModeShared),
            let found = context.device.makeBuffer(length: 4, options: .storageModeShared),
            let pairs = context.device.makeBuffer(length: tileCapacity * 8, options: .storageModeShared)
        else { throw GPUError.commandFailed("pair buffers") }
        let values = pairs.contents().bindMemory(to: UInt32.self, capacity: tileCapacity * 2)
        var count32 = UInt32(count)
        var distance32 = UInt32(maxDistance)
        var capacity32 = UInt32(tileCapacity)
        var result: [(Int, Int)] = []
        // One command buffer per tile keeps each GPU submission short (see GPUContext timing).
        for rowStart in stride(from: 0, to: count, by: pairTile) {
            for columnStart in stride(from: rowStart, to: count, by: pairTile) {
                try Task.checkCancellation()
                found.contents().storeBytes(of: UInt32(0), as: UInt32.self)
                var origin = SIMD2<UInt32>(UInt32(columnStart), UInt32(rowStart))
                let grid = MTLSize(
                    width: min(pairTile, count - columnStart), height: min(pairTile, count - rowStart), depth: 1)
                try context.run("hamming_pairs", grid: grid) { encoder in
                    encoder.setBuffer(hashBuffer, offset: 0, index: 0)
                    encoder.setBytes(&count32, length: 4, index: 1)
                    encoder.setBytes(&distance32, length: 4, index: 2)
                    encoder.setBuffer(found, offset: 0, index: 3)
                    encoder.setBuffer(pairs, offset: 0, index: 4)
                    encoder.setBytes(&capacity32, length: 4, index: 5)
                    encoder.setBytes(&origin, length: MemoryLayout<SIMD2<UInt32>>.stride, index: 6)
                }
                let total = Int(found.contents().load(as: UInt32.self))
                guard total <= tileCapacity else {
                    throw GPUError.commandFailed("too many similar pairs in one tile: \(total)")
                }
                for index in 0..<total {
                    result.append((Int(values[index * 2]), Int(values[index * 2 + 1])))
                }
            }
        }
        return result
    }
}
