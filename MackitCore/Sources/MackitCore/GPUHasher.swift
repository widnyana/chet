import Darwin
import Foundation
import Metal

/// 128-bit content digest computed on the GPU in 64 KB blocks. File chunks are read straight into
/// shared (unified) memory buffers. Not cryptographic: DuplicateFinder confirms matches byte for byte.
public struct GPUHasher: Sendable {
    static let blockSize = 65_536
    static let p1: UInt64 = 0x9E37_79B9_7F4A_7C15
    static let p2: UInt64 = 0xC2B2_AE3D_27D4_EB4F

    public let context: GPUContext
    /// Bytes per GPU dispatch. Must be a multiple of the 64 KB block size.
    public var chunkBytes = 64 << 20

    public init(context: GPUContext) {
        self.context = context
    }

    public func digest(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let blocksPerChunk = chunkBytes / Self.blockSize
        guard let buffer = context.device.makeBuffer(length: chunkBytes + 8, options: .storageModeShared),
            let out = context.device.makeBuffer(length: blocksPerChunk * 16, options: .storageModeShared)
        else { throw GPUError.commandFailed("hash buffers") }
        var blocks: [(UInt64, UInt64)] = []
        var total: UInt64 = 0
        var firstBlock: UInt32 = 0
        while true {
            try Task.checkCancellation()
            let read = try Self.readFully(handle.fileDescriptor, into: buffer.contents(), count: chunkBytes)
            if read == 0 { break }
            memset(buffer.contents().advanced(by: read), 0, 8)
            let blockCount = (read + Self.blockSize - 1) / Self.blockSize
            var count32 = UInt32(read)
            var first32 = firstBlock
            try context.run("block_hash", grid: MTLSize(width: blockCount, height: 1, depth: 1)) { encoder in
                encoder.setBuffer(buffer, offset: 0, index: 0)
                encoder.setBytes(&count32, length: 4, index: 1)
                encoder.setBytes(&first32, length: 4, index: 2)
                encoder.setBuffer(out, offset: 0, index: 3)
            }
            let values = out.contents().bindMemory(to: UInt64.self, capacity: blockCount * 2)
            for i in 0..<blockCount { blocks.append((values[i * 2], values[i * 2 + 1])) }
            total += UInt64(read)
            firstBlock += UInt32(blockCount)
            if read < chunkBytes { break }
        }
        return Self.combine(blocks, size: total)
    }

    /// CPU reference: same digest as `digest(_:)` for the same bytes.
    public static func cpuDigest(_ data: Data) -> String {
        var blocks: [(UInt64, UInt64)] = []
        data.withUnsafeBytes { bytes in
            var start = 0
            while start < bytes.count {
                let length = min(blockSize, bytes.count - start)
                blocks.append(blockHash(UnsafeRawBufferPointer(rebasing: bytes[start..<(start + length)]), index: UInt64(blocks.count)))
                start += length
            }
        }
        return combine(blocks, size: UInt64(data.count))
    }

    static func blockHash(_ bytes: UnsafeRawBufferPointer, index: UInt64) -> (UInt64, UInt64) {
        var a = p1 ^ (index &* p2)
        var b = p2 ^ (index &* p1)
        var offset = 0
        while offset < bytes.count {
            var word: UInt64 = 0
            withUnsafeMutableBytes(of: &word) { target in
                let take = min(8, bytes.count - offset)
                target.copyMemory(from: UnsafeRawBufferPointer(rebasing: bytes[offset..<(offset + take)]))
            }
            let v = UInt64(littleEndian: word)
            a = (a ^ v) &* p1
            a ^= a >> 29
            b = (b &+ v) &* p2
            b = (b << 31) | (b >> 33)
            offset += 8
        }
        let length = UInt64(bytes.count)
        return (a ^ length, b ^ (length &* p1))
    }

    static func combine(_ blocks: [(UInt64, UInt64)], size: UInt64) -> String {
        var x = size
        var y = ~size
        for (a, b) in blocks {
            x = (x ^ a) &* p1
            x ^= x >> 29
            y = (y &+ b) &* p2
            y = (y << 31) | (y >> 33)
        }
        return String(format: "%016llx%016llx", x, y)
    }

    static func readFully(_ fd: Int32, into pointer: UnsafeMutableRawPointer, count: Int) throws -> Int {
        var got = 0
        while got < count {
            let n = Darwin.read(fd, pointer.advanced(by: got), count - got)
            if n == 0 { break }
            if n < 0 {
                if errno == EINTR { continue }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            got += n
        }
        return got
    }
}
