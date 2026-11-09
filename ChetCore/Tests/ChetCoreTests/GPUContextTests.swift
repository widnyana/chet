import Metal
import Testing

@testable import ChetCore

struct GPUContextTests {
    @Test func initializesOnAppleGPU() throws {
        let gpu = try GPUContext()
        #expect(gpu.device.supportsFamily(.apple7))
    }

    @Test func addArraysMatchesCPU() throws {
        let gpu = try GPUContext()
        let n = 1 << 20
        let a = (0..<n).map { Float($0) }
        let b = (0..<n).map { Float($0) * 2 }
        let bytes = n * MemoryLayout<Float>.stride
        let bufA = try #require(gpu.device.makeBuffer(bytes: a, length: bytes, options: .storageModeShared))
        let bufB = try #require(gpu.device.makeBuffer(bytes: b, length: bytes, options: .storageModeShared))
        let out = try #require(gpu.device.makeBuffer(length: bytes, options: .storageModeShared))
        try gpu.run("add_arrays", grid: MTLSize(width: n, height: 1, depth: 1)) { encoder in
            encoder.setBuffer(bufA, offset: 0, index: 0)
            encoder.setBuffer(bufB, offset: 0, index: 1)
            encoder.setBuffer(out, offset: 0, index: 2)
        }
        let result = out.contents().bindMemory(to: Float.self, capacity: n)
        for i in stride(from: 0, to: n, by: 4099) {
            #expect(result[i] == a[i] + b[i])
        }
        #expect(result[n - 1] == a[n - 1] + b[n - 1])
    }

    @Test func missingFunctionThrows() throws {
        let gpu = try GPUContext()
        #expect(throws: GPUError.missingFunction("nope")) { try gpu.pipeline("nope") }
    }
}
