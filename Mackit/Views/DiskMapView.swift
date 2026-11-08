import AppKit
import MackitCore
import MetalKit
import SwiftUI

/// Deep inspection: a Metal-rendered nested treemap of the home folder that grows into its
/// final shape while the scan runs (walker rollups merge into `model.liveTree`), then swaps
/// to the full tree. Click a folder block to zoom in; each block paints its own children.
struct DiskMapView: View {
    @Environment(ScanModel.self) private var model
    /// Navigation path as URLs, not nodes: the live tree is replaced several times a second
    /// while scanning, so the current node is re-resolved from the newest tree every render.
    @State private var stack: [URL] = []
    /// Home tree of the finished scan; nil while the live tree is still growing.
    @State private var finalHome: FolderNode?
    /// Snapshot the UI draws. `liveTree` is replaced several times a second while the
    /// scan runs; feeding every replacement straight to the Metal canvas made the page
    /// flicker. The poll below publishes a 250 ms snapshot instead.
    @State private var displayTree: FolderNode?
    @State private var hovered: FolderNode?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if !pathNodes.isEmpty {
                    // One capsule for the whole path, not one per crumb.
                    HStack(spacing: 4) {
                        ForEach(Array(pathNodes.enumerated()), id: \.offset) { index, node in
                            if index > 0 {
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            Button(index == 0 ? "Home" : node.url.lastPathComponent) {
                                stack.removeSubrange((index + 1)...)
                            }
                            .buttonStyle(.plain)
                            .font(.callout)
                            .foregroundStyle(
                                index == pathNodes.count - 1 ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
                            )
                            .lineLimit(1)
                        }
                    }
                    .padding(.leading, 12)
                    .padding(.trailing, 8)
                    .padding(.vertical, 5)
                    .glassEffect(.regular, in: .capsule)
                }
                Spacer()
                legend
            }
            .padding(12)
            Divider()
            // Top section: the diagram. It grows live while the scan runs.
            if let current = pathNodes.last {
                TreemapCanvas(
                    node: current,
                    onHover: { hovered = $0 },
                    onOpen: { child in
                        if !child.children.isEmpty { stack.append(child.url) }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding([.horizontal, .bottom], 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            } else if !model.isScanning {
                ContentUnavailableView {
                    Label("Disk map", systemImage: "square.grid.3x3.fill")
                } description: {
                    Text("See which folders take the most space. Click a folder to look inside.")
                } actions: {
                    Button("Scan Now") { model.scan() }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Measuring, no rollup yet: keep the diagram section sized, blank.
                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // Bottom section: progress. Its per-tick text updates never touch the canvas.
            if model.isScanning {
                progressPanel
            }
        }
        .navigationTitle("Disk map")
        // The final trees replace the live render (same canvas, full data).
        .task(id: model.folderTrees) {
            guard !model.folderTrees.isEmpty else { return }
            let kids = model.folderTrees.sorted { $0.size > $1.size }
            finalHome = FolderNode(
                url: FileManager.default.homeDirectoryForCurrentUser, size: kids.reduce(0) { $0 + $1.size },
                children: kids)
            stack = []
            hovered = nil
        }
        // Publish a throttled tree snapshot and re-resolve the hover against it, so the
        // canvas and the path pill see a stable tree instead of every rollup.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let newest = model.liveTree ?? finalHome else { continue }
                guard newest != displayTree else { continue }
                displayTree = newest
                hovered = hovered.flatMap { Self.node(with: $0.url, in: newest) }
            }
        }
    }

    /// The newest node with this URL, or nil when the update dropped it.
    private static func node(with url: URL, in tree: FolderNode) -> FolderNode? {
        if tree.url == url { return tree }
        for child in tree.children {
            if let hit = node(with: url, in: child) { return hit }
        }
        return nil
    }

    /// Home tree first, then children along the navigation stack; the stack is trimmed to the
    /// prefix that still exists in the newest snapshot.
    private var pathNodes: [FolderNode] {
        guard var node = displayTree else { return [] }
        var nodes = [node]
        for url in stack {
            guard let child = node.children.first(where: { $0.url == url }) else { break }
            nodes.append(child)
            node = child
        }
        return nodes
    }

    /// Bottom section: everything the scan is doing right now, in one strip. Text-only,
    /// so its per-tick updates never relayout the Metal canvas above.
    private var progressPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if let activity = model.activity {
                    Text(headline(activity))
                        .font(.headline)
                        .monospacedDigit()
                        .lineLimit(1)
                    Spacer()
                    if let snap = model.rootsProgress {
                        Text(
                            "\(snap.files) files · \(snap.bytes.formatted(.byteCount(style: .file)))"
                                + " · root \(snap.rootsDone + 1) of \(snap.rootsTotal)"
                        )
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    }
                } else {
                    ProgressView().controlSize(.small)
                    Text(model.currentStep?.title ?? "Starting scan")
                        .font(.headline)
                }
            }
            if let activity = model.activity {
                // Determinate only when the phase has a denominator that can actually grow.
                Group {
                    if activity.total > activity.done, activity.total > 0 {
                        ProgressView(value: Double(activity.done), total: Double(activity.total))
                    } else {
                        ProgressView()
                    }
                }
                .progressViewStyle(.linear)
                Text(detailLine(activity))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(activity.label)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(activity.trail.prefix(5).enumerated()), id: \.offset) { index, label in
                        Text(label)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(index == 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            HStack(spacing: 10) {
                Spacer()
                Button(model.isPaused ? "Resume" : "Pause") { model.togglePause() }
                    .controlSize(.small)
                Button("Stop", systemImage: "stop.fill") { model.cancel() }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.4))
        .overlay(alignment: .top) { Divider() }
    }

    /// "<phase title>" plus its fraction when the phase knows one.
    private func headline(_ activity: ScanActivity) -> String {
        var parts = [activity.phase.title]
        if activity.total > activity.done, activity.total > 0 {
            parts.append("\(activity.done) of \(activity.total)")
        }
        if model.isPaused { parts.append("paused") }
        return parts.joined(separator: " — ")
    }

    /// The active label plus rate, elapsed, and paused state.
    private func detailLine(_ activity: ScanActivity) -> String {
        var parts = [activity.label]
        if let rate = model.rate { parts.append(String(format: "%.1fk files/s", rate)) }
        if let started = model.scanStartedAt { parts.append(Self.elapsed(since: started)) }
        if model.isPaused { parts.append("paused") }
        return parts.joined(separator: " · ")
    }

    static func elapsed(since date: Date) -> String {
        let interval = Int(Date().timeIntervalSince(date))
        return String(format: "%02d:%02d", interval / 60, interval % 60)
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
        // FolderNode is Equatable: relayout on any structural change (sizes grow live
        // during a scan even though the URL stays the same).
        if view.node != node {
            view.node = node
            view.relayout()
        }
    }
}

/// One drawable rectangle of the nested treemap: its frame, fill color, and the node it
/// represents (for hover and click). Ancestors come before descendants, so painting in list
/// order layers children on top of their parent block.
struct TreemapTile {
    let rect: CGRect
    let color: SIMD4<Float>
    let node: FolderNode
}

final class TreemapMTKView: MTKView, MTKViewDelegate {
    var node: FolderNode?
    var onHover: (FolderNode?) -> Void = { _ in }
    var onOpen: (FolderNode) -> Void = { _ in }
    private var tiles: [TreemapTile] = []
    private var instances: MTLBuffer?
    private var pipeline: MTLRenderPipelineState?

    /// How many nested levels are drawn: the node itself plus this many child levels.
    static let nestingLevels = 3
    /// A block recurses into its children only when it is big enough for them to be legible.
    static let minRecursionFraction: CGFloat = 0.015

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
        tiles = Self.tiles(for: node, in: CGRect(origin: .zero, size: bounds.size))
        var data: [SIMD4<Float>] = []
        for tile in tiles {
            let r = tile.rect
            data.append(
                SIMD4(
                    Float(r.minX / bounds.width), Float(r.minY / bounds.height), Float(r.width / bounds.width),
                    Float(r.height / bounds.height)))
            data.append(tile.color)
        }
        instances =
            data.isEmpty ? nil : device.makeBuffer(bytes: data, length: data.count * MemoryLayout<SIMD4<Float>>.stride)
        needsDisplay = true
    }

    /// Nested layout (V4): squarify the children, inset each child rect so the parent's color
    /// shows as a border, then recurse into children that are large enough to be legible.
    static func tiles(for node: FolderNode, in bounds: CGRect, level: Int = 0) -> [TreemapTile] {
        guard !node.children.isEmpty else { return [] }
        var out = [
            TreemapTile(rect: bounds, color: Self.dimmed(Self.color(for: node.url)), node: node)
        ]
        let rects = Treemap.layout(node.children.map(\.size), in: bounds)
        for item in rects where item.rect.width > 4 && item.rect.height > 4 {
            let child = node.children[item.index]
            let inner = item.rect.insetBy(dx: 1, dy: 1)
            out.append(TreemapTile(rect: inner, color: Self.color(for: child.url), node: child))
            if level < nestingLevels - 1, !child.children.isEmpty,
                inner.width * inner.height >= bounds.width * bounds.height * minRecursionFraction
            {
                out.append(
                    contentsOf: tiles(for: child, in: inner.insetBy(dx: 3, dy: 3), level: level + 1))
            }
        }
        return out
    }

    private static func dimmed(_ color: SIMD4<Float>) -> SIMD4<Float> {
        SIMD4(color.x * 0.72, color.y * 0.72, color.z * 0.72, 1)
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
        if let pipeline, let instances, !tiles.isEmpty {
            var viewport = SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height))
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBuffer(instances, offset: 0, index: 0)
            encoder.setVertexBytes(&viewport, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: tiles.count)
        }
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    /// Deepest tile containing the point (V4): smallest area wins, so grandchildren beat
    /// their parent block even where the parent's border gap shows through.
    private func tile(at point: CGPoint) -> TreemapTile? {
        tiles
            .filter { $0.rect.contains(point) }
            .min { $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height }
    }

    override func mouseMoved(with event: NSEvent) {
        onHover(tile(at: convert(event.locationInWindow, from: nil))?.node)
    }
    override func mouseExited(with event: NSEvent) { onHover(nil) }

    override func mouseDown(with event: NSEvent) {
        if let node = tile(at: convert(event.locationInWindow, from: nil))?.node, !node.children.isEmpty {
            onOpen(node)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let child = tile(at: convert(event.locationInWindow, from: nil))?.node else { return nil }
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

    /// The legend colors: orange caches and logs, purple developer data, green media, blue other.
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
