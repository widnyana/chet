import Foundation
import Metal

public enum GPUError: Error, Equatable {
    case noDevice
    case missingShaders
    case missingFunction(String)
    case commandFailed(String)
}

/// Shared Metal device, queue and shader library. Shaders are `.metal` text resources
/// compiled at runtime, because `swift build` / `swift test` do not compile `.metal` files.
public final class GPUContext: @unchecked Sendable {
    public static let shared: GPUContext? = try? GPUContext()

    public let device: MTLDevice
    public let queue: MTLCommandQueue
    private let library: MTLLibrary
    private let lock = NSLock()
    private var pipelines: [String: MTLComputePipelineState] = [:]

    public init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw GPUError.noDevice
        }
        self.device = device
        self.queue = queue
        library = try device.makeLibrary(source: Self.shaderSource(), options: nil)
    }

    static func shaderSource() throws -> String {
        guard let dir = Bundle.module.url(forResource: "Shaders", withExtension: nil) else {
            throw GPUError.missingShaders
        }
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "metal" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !files.isEmpty else { throw GPUError.missingShaders }
        return try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
    }

    public func pipeline(_ name: String) throws -> MTLComputePipelineState {
        lock.lock()
        defer { lock.unlock() }
        if let cached = pipelines[name] { return cached }
        guard let function = library.makeFunction(name: name) else { throw GPUError.missingFunction(name) }
        let state = try device.makeComputePipelineState(function: function)
        pipelines[name] = state
        return state
    }

    /// Runs kernel `name` over `grid` threads and waits for it to finish.
    public func run(_ name: String, grid: MTLSize, encode: (MTLComputeCommandEncoder) -> Void) throws {
        let state = try pipeline(name)
        guard let buffer = queue.makeCommandBuffer(), let encoder = buffer.makeComputeCommandEncoder() else {
            throw GPUError.commandFailed(name)
        }
        encoder.setComputePipelineState(state)
        encode(encoder)
        let width = state.threadExecutionWidth
        let group =
            grid.height > 1
            ? MTLSize(width: width, height: max(1, state.maxTotalThreadsPerThreadgroup / width), depth: 1)
            : MTLSize(width: max(1, min(state.maxTotalThreadsPerThreadgroup, grid.width)), height: 1, depth: 1)
        encoder.dispatchThreads(grid, threadsPerThreadgroup: group)
        encoder.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()
        if let error = buffer.error { throw GPUError.commandFailed(error.localizedDescription) }
    }
}
