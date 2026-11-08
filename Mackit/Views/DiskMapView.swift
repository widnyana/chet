import AppKit
import MackitCore
import MetalKit
import SwiftUI

/// Deep inspection: a Metal-rendered nested treemap of the home folder that grows into its
/// final shape while the scan runs (walker rollups merge into `model.liveTree`), then swaps
/// to the full tree. Click a folder block to zoom in; each block paints its own children.
struct DiskMapView: View {
    @Environment(ScanModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
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
    /// Name + size labels for the top-tier blocks, published by the Metal view.
    @State private var labels: [TreemapLabel] = []

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        VStack(spacing: 0) {
            DiskMapChrome(
                pathNodes: pathNodes,
                isDark: isDark,
                onSelect: { index in
                    stack.removeSubrange((index + 1)...)
                })
            // Top section: the diagram. It grows live while the scan runs.
            if let current = pathNodes.last {
                TreemapCanvas(
                    node: current,
                    isDark: isDark,
                    onHover: { hovered = $0 },
                    onOpen: { child in
                        if !child.children.isEmpty { stack.append(child.url) }
                    },
                    onLabels: { labels = $0 }
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, Spacing.s6)
                .padding(.bottom, Spacing.s3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    // Direct labels on the top tier: the biggest folders read without
                    // hovering. Coordinates are the canvas layout's own, top-left origin.
                    GeometryReader { geo in
                        ForEach(labels) { label in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(label.title)
                                    .font(Typography.section)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Text(label.subtitle)
                                    .font(Typography.caption)
                                    .monospacedDigit()
                                    .lineLimit(1)
                            }
                            .foregroundStyle(
                                label.darkText
                                    ? Color(red: 0.07, green: 0.08, blue: 0.09)
                                    : Color.white
                            )
                            .frame(maxWidth: label.rect.width - 12, alignment: .leading)
                            .offset(x: label.rect.minX + 8, y: label.rect.minY + 8)
                        }
                    }
                    .allowsHitTesting(false)
                }
                .overlay(alignment: .bottomLeading) {
                    if let hovered {
                        HStack(spacing: Spacing.s2) {
                            Text(hovered.url.lastPathComponent)
                                .font(Typography.row)
                                .fontWeight(.medium)
                                .foregroundStyle(Theme.ink)
                            Text(hovered.size.formatted(.byteCount(style: .file)))
                                .font(Typography.row)
                                .monospacedDigit()
                                .foregroundStyle(Theme.inkSecondary)
                        }
                        .padding(.horizontal, Spacing.s3)
                        .padding(.vertical, Spacing.s1)
                        .background(Theme.paperRaised, in: RoundedRectangle(cornerRadius: 4))
                        .overlay {
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Theme.hairline, lineWidth: 1)
                        }
                        .padding(Spacing.s6)
                        .allowsHitTesting(false)
                    }
                }
            } else if !model.isScanning {
                EmptyStateView(
                    title: "No disk map yet",
                    message: "Run a scan to see where the space is. Click a folder to look inside.",
                    actionTitle: "Scan this Mac",
                    action: { model.scan() }
                )
                .padding(Spacing.s8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: Spacing.s2) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Measuring your folders")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // Bottom section: progress. Its per-tick text updates never touch the canvas.
            if model.isScanning {
                progressPanel
            }
        }
        .background(Theme.paper)
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
        VStack(spacing: 0) {
            Hairline()
            VStack(alignment: .leading, spacing: Spacing.s2) {
                HStack(spacing: Spacing.s2) {
                    if let activity = model.activity {
                        Text(headline(activity))
                            .font(Typography.section)
                            .monospacedDigit()
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Spacer()
                        if let snap = model.rootsProgress {
                            Text(
                                "\(snap.files) files · \(snap.bytes.formatted(.byteCount(style: .file)))"
                                    + " · root \(snap.rootsDone + 1) of \(snap.rootsTotal)"
                            )
                            .font(Typography.caption)
                            .monospacedDigit()
                            .foregroundStyle(Theme.inkSecondary)
                        }
                    } else {
                        ProgressView().controlSize(.small)
                        Text(model.currentStep?.title ?? "Starting scan")
                            .font(Typography.section)
                            .foregroundStyle(Theme.ink)
                    }
                }
                if let activity = model.activity {
                    Group {
                        if activity.total > activity.done, activity.total > 0 {
                            ProgressView(value: Double(activity.done), total: Double(activity.total))
                        } else {
                            ProgressView()
                        }
                    }
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
                    Text(detailLine(activity))
                        .font(Typography.row)
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(activity.label)
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(activity.trail.prefix(5).enumerated()), id: \.offset) { index, label in
                            Text(label)
                                .font(Typography.caption)
                                .monospacedDigit()
                                .foregroundStyle(index == 0 ? Theme.ink : Theme.inkTertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                HStack(spacing: Spacing.s2) {
                    Spacer()
                    Button(model.isPaused ? "Resume" : "Pause") { model.togglePause() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("Stop", systemImage: "stop.fill") { model.cancel() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, Spacing.s6)
            .padding(.vertical, Spacing.s2)
            .background(Theme.paper)
        }
    }

    /// "<phase title>" plus its fraction when the phase knows one.
    private func headline(_ activity: ScanActivity) -> String {
        var parts = [activity.phase.title]
        if activity.total > activity.done, activity.total > 0 {
            parts.append("\(activity.done) of \(activity.total)")
        }
        if model.isPaused { parts.append("paused") }
        return parts.joined(separator: " · ")
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

}

struct DiskMapChrome: View {
    let pathNodes: [FolderNode]
    let isDark: Bool
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.s2) {
                HStack(spacing: Spacing.s1) {
                    ForEach(Array(pathNodes.enumerated()), id: \.offset) { index, node in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(Typography.caption)
                                .foregroundStyle(Theme.inkTertiary)
                        }
                        Button(index == 0 ? "Home" : node.url.lastPathComponent) {
                            onSelect(index)
                        }
                        .buttonStyle(.plain)
                        .font(Typography.caption)
                        .foregroundStyle(index == pathNodes.count - 1 ? Theme.ink : Theme.inkSecondary)
                        .lineLimit(1)
                    }
                }
                Spacer()
                legend
            }
            .padding(.horizontal, Spacing.s6)
            .padding(.vertical, Spacing.s2)
            Hairline()
        }
        .background(Theme.paper)
    }

    private var legend: some View {
        HStack(spacing: Spacing.s2) {
            ForEach(0..<4, id: \.self) { step in
                RoundedRectangle(cornerRadius: 1)
                    .fill(swatch(step))
                    .frame(width: 10, height: 10)
            }
            Text(isDark ? "Lighter means a larger share" : "Darker means a larger share")
                .font(Typography.caption)
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    private func swatch(_ step: Int) -> Color {
        let palette = TreemapPalette(isDark: isDark)
        let color = palette.ramp(CGFloat(step) / 3)
        return Color(.sRGB, red: Double(color.x), green: Double(color.y), blue: Double(color.z), opacity: 1)
    }
}

struct TreemapCanvas: NSViewRepresentable {
    let node: FolderNode
    let isDark: Bool
    let onHover: (FolderNode?) -> Void
    let onOpen: (FolderNode) -> Void
    let onLabels: ([TreemapLabel]) -> Void

    func makeNSView(context: Context) -> TreemapMTKView {
        let view = TreemapMTKView(frame: .zero, device: GPUContext.shared?.device)
        view.isDark = isDark
        view.configure()
        return view
    }

    func updateNSView(_ view: TreemapMTKView, context: Context) {
        view.onHover = onHover
        view.onOpen = onOpen
        view.onLabels = onLabels
        let appearanceChanged = view.isDark != isDark
        view.isDark = isDark
        // FolderNode is Equatable: relayout on any structural change (sizes grow live
        // during a scan even though the URL stays the same).
        if view.node != node || appearanceChanged {
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
    let border: SIMD4<Float>
    let node: FolderNode
}

/// A name and byte count drawn directly on a big top-level block.
struct TreemapLabel: Identifiable {
    let rect: CGRect
    let title: String
    let subtitle: String
    let darkText: Bool
    var id: CGRect { rect }
}

/// One neutral ramp, read in one direction per appearance. Small blocks sit near
/// the paper, large blocks sit near the ink.
struct TreemapPalette {
    let isDark: Bool

    var background: SIMD4<Float> {
        isDark ? SIMD4(0.071, 0.075, 0.086, 1) : SIMD4(0.965, 0.957, 0.937, 1)
    }

    var border: SIMD4<Float> { background }

    func ramp(_ t: CGFloat) -> SIMD4<Float> {
        let t = Float(min(1, max(0, t)))
        let start: SIMD3<Float> = isDark ? SIMD3(0.165, 0.173, 0.192) : SIMD3(0.894, 0.878, 0.843)
        let end: SIMD3<Float> = isDark ? SIMD3(0.847, 0.831, 0.796) : SIMD3(0.114, 0.125, 0.149)
        let color = start + (end - start) * t
        return SIMD4(color.x, color.y, color.z, 1)
    }

    func rampShare(_ share: CGFloat) -> SIMD4<Float> {
        ramp(CGFloat(sqrt(max(0, share))))
    }

    func labelIsDark(_ share: CGFloat) -> Bool {
        let t = sqrt(max(0, share))
        return isDark ? t > 0.45 : t < 0.45
    }
}

final class TreemapMTKView: MTKView, MTKViewDelegate {
    var node: FolderNode?
    var isDark = false
    var onHover: (FolderNode?) -> Void = { _ in }
    var onOpen: (FolderNode) -> Void = { _ in }
    /// Publishes the top-tier labels (name + size on big blocks) to the SwiftUI layer.
    var onLabels: ([TreemapLabel]) -> Void = { _ in }
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
        let palette = TreemapPalette(isDark: isDark)
        tiles = Self.tiles(for: node, in: CGRect(origin: .zero, size: bounds.size), palette: palette)
        var data: [SIMD4<Float>] = []
        for tile in tiles {
            let r = tile.rect
            data.append(
                SIMD4(
                    Float(r.minX / bounds.width), Float(r.minY / bounds.height), Float(r.width / bounds.width),
                    Float(r.height / bounds.height)))
            data.append(tile.color)
            data.append(tile.border)
        }
        instances =
            data.isEmpty ? nil : device.makeBuffer(bytes: data, length: data.count * MemoryLayout<SIMD4<Float>>.stride)
        needsDisplay = true
        onLabels(Self.labels(for: node, in: bounds, palette: palette))
    }

    /// Labels for top-level children big enough to carry two lines of text (84 pt a
    /// side). Shares mirror `tiles(for:in:level:)`, so label rects match the canvas.
    static func labels(for node: FolderNode, in bounds: CGRect, palette: TreemapPalette) -> [TreemapLabel] {
        guard !node.children.isEmpty, bounds.width > 0 else { return [] }
        let boundsArea = bounds.width * bounds.height
        var out: [TreemapLabel] = []
        for item in Treemap.layout(node.children.map(\.size), in: bounds)
        where item.rect.width >= 84 && item.rect.height >= 84 {
            let child = node.children[item.index]
            let share = boundsArea > 0 ? item.rect.width * item.rect.height / boundsArea : 0
            let t = sqrt(max(0, share))
            // Mid-tone fills cannot carry either ink or paper text at AA contrast.
            // Keep the labels on the light and dark ends; hover covers the middle.
            guard t < 0.45 || t > 0.78 else { continue }
            out.append(
                TreemapLabel(
                    rect: item.rect,
                    title: child.url.lastPathComponent,
                    subtitle: child.size.formatted(.byteCount(style: .file)),
                    darkText: palette.labelIsDark(share)))
        }
        return out
    }

    /// Nested layout (V4): squarify the children, inset each child rect so the parent's color
    /// shows as a border, then recurse into children that are large enough to be legible.
    static func tiles(
        for node: FolderNode, in bounds: CGRect, level: Int = 0, palette: TreemapPalette
    ) -> [TreemapTile] {
        guard !node.children.isEmpty else { return [] }
        var out = [
            TreemapTile(rect: bounds, color: palette.background, border: palette.border, node: node)
        ]
        let rects = Treemap.layout(node.children.map(\.size), in: bounds)
        let boundsArea = bounds.width * bounds.height
        for item in rects where item.rect.width > 4 && item.rect.height > 4 {
            let child = node.children[item.index]
            let inner = item.rect.insetBy(dx: 1, dy: 1)
            let share = boundsArea > 0 ? item.rect.width * item.rect.height / boundsArea : 0
            out.append(
                TreemapTile(
                    rect: inner,
                    color: palette.rampShare(share),
                    border: palette.border,
                    node: child))
            if level < nestingLevels - 1, !child.children.isEmpty,
                inner.width * inner.height >= boundsArea * minRecursionFraction
            {
                out.append(
                    contentsOf: tiles(
                        for: child, in: inner.insetBy(dx: 3, dy: 3), level: level + 1, palette: palette))
            }
        }
        return out
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

}
