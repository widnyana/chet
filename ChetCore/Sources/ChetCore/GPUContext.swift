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
    private var lastSeconds: Double = 0
    private var maxSeconds: Double = 0

    /// GPU time of the most recent command buffer, and the longest one since the last reset.
    /// Long command buffers starve WindowServer, so tests and the scan benchmark watch these.
    public var lastGPUSeconds: Double { lock.withLock { lastSeconds } }
    public var maxGPUSeconds: Double { lock.withLock { maxSeconds } }

    public func resetGPUTiming() {
        lock.withLock {
            lastSeconds = 0
            maxSeconds = 0
        }
    }

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

    public func renderPipeline(vertex: String, fragment: String, pixelFormat: MTLPixelFormat) throws
        -> MTLRenderPipelineState
    {
        guard let vertexFunction = library.makeFunction(name: vertex) else { throw GPUError.missingFunction(vertex) }
        guard let fragmentFunction = library.makeFunction(name: fragment) else {
            throw GPUError.missingFunction(fragment)
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    /// Runs kernel `name` over `grid` threads and waits for it to finish.
    public func run(_ name: String, grid: MTLSize, encode: (MTLComputeCommandEncoder) -> Void) throws {
        try submit(name, encode) { encoder, state in
            let width = state.threadExecutionWidth
            let group =
                grid.height > 1
                ? MTLSize(width: width, height: max(1, state.maxTotalThreadsPerThreadgroup / width), depth: 1)
                : MTLSize(width: max(1, min(state.maxTotalThreadsPerThreadgroup, grid.width)), height: 1, depth: 1)
            encoder.dispatchThreads(grid, threadsPerThreadgroup: group)
        }
    }

    /// Runs kernel `name` over a count of threadgroups and waits. Use this when threads inside a
    /// group cooperate through threadgroup memory: the grid is then groups, not threads.
    public func run(
        _ name: String, threadgroups: MTLSize, threadsPerThreadgroup: MTLSize,
        encode: (MTLComputeCommandEncoder) -> Void
    ) throws {
        try submit(name, encode) { encoder, _ in
            encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
        }
    }

    private func submit(
        _ name: String, _ encode: (MTLComputeCommandEncoder) -> Void,
        dispatch: (MTLComputeCommandEncoder, MTLComputePipelineState) -> Void
    ) throws {
        let state = try pipeline(name)
        guard let buffer = queue.makeCommandBuffer(), let encoder = buffer.makeComputeCommandEncoder() else {
            throw GPUError.commandFailed(name)
        }
        encoder.setComputePipelineState(state)
        encode(encoder)
        dispatch(encoder, state)
        encoder.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()
        let seconds = max(0, buffer.gpuEndTime - buffer.gpuStartTime)
        lock.withLock {
            lastSeconds = seconds
            maxSeconds = max(maxSeconds, seconds)
        }
        if let error = buffer.error { throw GPUError.commandFailed(error.localizedDescription) }
    }
}
