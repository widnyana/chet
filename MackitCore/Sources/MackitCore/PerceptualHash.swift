import CoreGraphics
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

    /// cos((2x + 1) u pi / 64) * 1024, rounded, for u in 0..<8 and x in 0..<32 (index u * 32 + x).
    static let cosTable: [Int32] = (0..<8).flatMap { u in
        (0..<32).map { x in Int32((cos(Double((2 * x + 1) * u) * .pi / 64) * 1024).rounded()) }
    }

    /// Decodes an image file into a side x side RGBA bitmap (stretched). Also returns the original pixel count.
    /// Nil when the file is not a decodable image.
    public static func bitmap(_ url: URL) -> (rgba: [UInt8], pixels: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: side,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
            let rgba = bitmap(thumbnail)
        else { return nil }
        return (rgba, width * height)
    }

    /// Draws an image into a side x side RGBA bitmap (stretched).
    public static func bitmap(_ image: CGImage) -> [UInt8]? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var rgba = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn ? rgba : nil
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

    public static func gpu(_ batch: [[UInt8]], context: GPUContext) throws -> [Features] {
        let count = batch.count
        guard count > 0 else { return [] }
        let imageBytes = side * side * 4
        guard let input = context.device.makeBuffer(length: count * imageBytes, options: .storageModeShared),
            let table = context.device.makeBuffer(
                bytes: cosTable, length: cosTable.count * MemoryLayout<Int32>.stride, options: .storageModeShared),
            let hashes = context.device.makeBuffer(length: count * 8, options: .storageModeShared),
            let lap = context.device.makeBuffer(length: count * 16, options: .storageModeShared)
        else { throw GPUError.commandFailed("photo buffers") }
        for (index, rgba) in batch.enumerated() {
            rgba.withUnsafeBytes { bytes in
                input.contents().advanced(by: index * imageBytes)
                    .copyMemory(from: bytes.baseAddress!, byteCount: imageBytes)
            }
        }
        try context.run("photo_features", grid: MTLSize(width: count, height: 1, depth: 1)) { encoder in
            encoder.setBuffer(input, offset: 0, index: 0)
            encoder.setBuffer(table, offset: 0, index: 1)
            encoder.setBuffer(hashes, offset: 0, index: 2)
            encoder.setBuffer(lap, offset: 0, index: 3)
        }
        let hashValues = hashes.contents().bindMemory(to: UInt64.self, capacity: count)
        let lapValues = lap.contents().bindMemory(to: Int64.self, capacity: count * 2)
        return (0..<count).map {
            Features(hash: hashValues[$0], lapSum: lapValues[$0 * 2], lapSquares: lapValues[$0 * 2 + 1])
        }
    }

    public static func hamming(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }

    public static func cpuPairs(_ hashes: [UInt64], maxDistance: Int) -> [(Int, Int)] {
        var pairs: [(Int, Int)] = []
        for i in hashes.indices {
            for j in (i + 1)..<hashes.count where hamming(hashes[i], hashes[j]) <= maxDistance { pairs.append((i, j)) }
        }
        return pairs
    }

    public static func gpuPairs(
        _ hashes: [UInt64], maxDistance: Int, context: GPUContext, capacity: Int = 1 << 20
    ) throws -> [(Int, Int)] {
        let count = hashes.count
        guard count > 1 else { return [] }
        guard
            let hashBuffer = context.device.makeBuffer(
                bytes: hashes, length: count * 8, options: .storageModeShared),
            let found = context.device.makeBuffer(length: 4, options: .storageModeShared),
            let pairs = context.device.makeBuffer(length: capacity * 8, options: .storageModeShared)
        else { throw GPUError.commandFailed("pair buffers") }
        found.contents().storeBytes(of: UInt32(0), as: UInt32.self)
        var count32 = UInt32(count)
        var distance32 = UInt32(maxDistance)
        var capacity32 = UInt32(capacity)
        try context.run("hamming_pairs", grid: MTLSize(width: count, height: count, depth: 1)) { encoder in
            encoder.setBuffer(hashBuffer, offset: 0, index: 0)
            encoder.setBytes(&count32, length: 4, index: 1)
            encoder.setBytes(&distance32, length: 4, index: 2)
            encoder.setBuffer(found, offset: 0, index: 3)
            encoder.setBuffer(pairs, offset: 0, index: 4)
            encoder.setBytes(&capacity32, length: 4, index: 5)
        }
        let total = Int(found.contents().load(as: UInt32.self))
        guard total <= capacity else { throw GPUError.commandFailed("too many similar pairs: \(total)") }
        let values = pairs.contents().bindMemory(to: UInt32.self, capacity: capacity * 2)
        return (0..<total).map { (Int(values[$0 * 2]), Int(values[$0 * 2 + 1])) }
    }
}
