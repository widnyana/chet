import AppKit
import MackitCore
import MetalKit
import SwiftUI

/// Deep inspection: a Metal-rendered treemap of the home folder. Click a folder to zoom in.
struct DiskMapView: View {
    @Environment(ScanModel.self) private var model
    @State private var stack: [FolderNode] = []
    @State private var hovered: FolderNode?
    @State private var loading = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(Array(stack.enumerated()), id: \.offset) { index, node in
                    if index > 0 {
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    Button(index == 0 ? "Home" : node.url.lastPathComponent) {
                        stack.removeSubrange((index + 1)...)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
                Spacer()
                if !stack.isEmpty { legend }
            }
            .padding(12)
            if let current = stack.last {
                TreemapCanvas(
                    node: current,
                    onHover: { hovered = $0 },
                    onOpen: { child in
                        if !child.children.isEmpty { stack.append(child) }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding([.horizontal, .bottom], 12)
                .overlay(alignment: .bottomLeading) {
                    if let hovered {
                        HStack(spacing: 8) {
                            Text(hovered.url.lastPathComponent).fontWeight(.medium)
                            Text(hovered.size.formatted(.byteCount(style: .file)))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .glassEffect(.regular, in: .capsule)
                        .padding(24)
                        .allowsHitTesting(false)
                    }
                }
            } else if loading {
                ProgressView("Measuring folders")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label("Disk map", systemImage: "square.grid.3x3.fill")
                } description: {
                    Text("See which folders take the most space. Click a folder to look inside.")
                } actions: {
                    Button("Map Home Folder") { Task { await load() } }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                }
            }
        }
        .navigationTitle("Disk map")
    }

    private var legend: some View {
        HStack(spacing: 12) {
            ForEach(
                [("Caches and logs", Color.orange), ("Developer", .purple), ("Media", .green), ("Other", .blue)],
                id: \.0
            ) { item in
                HStack(spacing: 4) {
                    Circle().fill(item.1).frame(width: 8, height: 8)
                    Text(item.0)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func load() async {
        loading = true
        if !model.folderTrees.isEmpty {
            let kids = model.folderTrees.sorted { $0.size > $1.size }
            stack = [
                FolderNode(
                    url: FileManager.default.homeDirectoryForCurrentUser, size: kids.reduce(0) { $0 + $1.size },
                    children: kids)
            ]
            loading = false
            return
        }
        if let root = await Self.build(FileManager.default.homeDirectoryForCurrentUser) { stack = [root] }
        loading = false
    }

    @concurrent nonisolated static func build(_ root: URL) async -> FolderNode? {
        try? FolderTree.build(root, policy: SafetyPolicy(home: root), maxDepth: 6)
    }
}

struct TreemapCanvas: NSViewRepresentable {
    let node: FolderNode
    let onHover: (FolderNode?) -> Void
    let onOpen: (FolderNode) -> Void

    func makeNSView(context: Context) -> TreemapMTKView {
        let view = TreemapMTKView(frame: .zero, device: GPUContext.shared?.device)
        view.configure()
        return view
    }

    func updateNSView(_ view: TreemapMTKView, context: Context) {
        view.onHover = onHover
        view.onOpen = onOpen
        if view.node?.url != node.url {
            view.node = node
            view.relayout()
        }
    }
}

final class TreemapMTKView: MTKView, MTKViewDelegate {
    var node: FolderNode?
    var onHover: (FolderNode?) -> Void = { _ in }
    var onOpen: (FolderNode) -> Void = { _ in }
    private var rects: [TreemapRect] = []
    private var instances: MTLBuffer?
    private var pipeline: MTLRenderPipelineState?

    override var isFlipped: Bool { true }

    func configure() {
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        enableSetNeedsDisplay = true
        isPaused = true
        delegate = self
        pipeline = try? GPUContext.shared?.renderPipeline(
            vertex: "treemap_vertex", fragment: "treemap_fragment", pixelFormat: colorPixelFormat)
        addTrackingArea(
            NSTrackingArea(
                rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self))
    }

    func relayout() {
        guard let node, bounds.width > 0, bounds.height > 0, let device else { return }
        rects = Treemap.layout(node.children.map(\.size), in: CGRect(origin: .zero, size: bounds.size))
        var data: [SIMD4<Float>] = []
        for item in rects {
            let r = item.rect
            data.append(
                SIMD4(
                    Float(r.minX / bounds.width), Float(r.minY / bounds.height), Float(r.width / bounds.width),
                    Float(r.height / bounds.height)))
            data.append(Self.color(for: node.children[item.index].url))
        }
        instances =
            data.isEmpty ? nil : device.makeBuffer(bytes: data, length: data.count * MemoryLayout<SIMD4<Float>>.stride)
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        relayout()
    }

    func draw(in view: MTKView) {
        guard let pass = currentRenderPassDescriptor, let drawable = currentDrawable,
            let buffer = GPUContext.shared?.queue.makeCommandBuffer(),
            let encoder = buffer.makeRenderCommandEncoder(descriptor: pass)
        else { return }
        if let pipeline, let instances, !rects.isEmpty {
            var viewport = SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height))
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBuffer(instances, offset: 0, index: 0)
            encoder.setVertexBytes(&viewport, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: rects.count)
        }
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    private func child(at event: NSEvent) -> FolderNode? {
        let point = convert(event.locationInWindow, from: nil)
        guard let node, let index = Treemap.hitTest(rects, point) else { return nil }
        return node.children[index]
    }

    override func mouseMoved(with event: NSEvent) { onHover(child(at: event)) }
    override func mouseExited(with event: NSEvent) { onHover(nil) }

    override func mouseDown(with event: NSEvent) {
        if let child = child(at: event) { onOpen(child) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let child = child(at: event) else { return nil }
        let menu = NSMenu()
        let item = NSMenuItem(title: "Reveal in Finder", action: #selector(reveal(_:)), keyEquivalent: "")
        item.representedObject = child.url
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc private func reveal(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    /// Orange: caches and logs. Purple: developer data. Green: media. Blue: everything else.
    static func color(for url: URL) -> SIMD4<Float> {
        let path = url.path
        if path.contains("/Caches") || path.contains("/Logs") { return SIMD4(0.95, 0.55, 0.25, 1) }
        if ["/Developer", "/node_modules", "/DerivedData", "/.build"].contains(where: { path.contains($0) }) {
            return SIMD4(0.55, 0.45, 0.85, 1)
        }
        if ["/Pictures", "/Movies", "/Music"].contains(where: { path.contains($0) }) {
            return SIMD4(0.3, 0.7, 0.45, 1)
        }
        return SIMD4(0.35, 0.55, 0.85, 1)
    }
}
