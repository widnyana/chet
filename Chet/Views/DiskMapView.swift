import AppKit
import ChetCore
import MetalKit
import SwiftUI

/// Deep inspection: a Metal-rendered nested treemap of the home folder that grows into its
/// final shape while the scan runs (walker rollups merge into `model.liveTree`), then swaps
/// to the full tree. One surface for reading and acting: the chart, the child ledger, and the
/// command bar share one collection, and the collection moves to the Trash together.
struct DiskMapView: View {
    @Environment(ScanModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    /// Sidebar destination, so the metric links can open Home or the large-files category.
    @Binding var destination: String?

    /// Home tree of the finished scan; nil while the live tree is still growing.
    @State private var finalHome: FolderNode?
    /// Snapshot the UI draws. `liveTree` is replaced several times a second while the
    /// scan runs; feeding every replacement straight to the Metal canvas made the page
    /// flicker. The poll below publishes a 250 ms snapshot instead.
    @State private var tree: FolderNode?
    /// Path within `tree` from its root to the folder on screen. Nodes, not URLs, so the
    /// breadcrumb, canvas, and ledger render one resolved state instead of each
    /// re-resolving a URL stack against a tree that keeps changing.
    @State private var crumbs: [FolderNode] = []
    @State private var hovered: FolderNode?
    /// Canvas frame size; the block labels are laid out with the same size the Metal
    /// tiles use, so a label cannot outlive the tile it names.
    @State private var canvasSize: CGSize = .zero
    /// Collected children, keyed by URL. Survives drill-down and drill-out.
    @State private var collection: [URL: StorageEntry] = [:]
    @State private var volume: VolumeCapacity?
    /// Frozen when the sheet opens, so the list cannot change under the user. The
    /// item form gives the sheet the exact entries that opened it.
    @State private var trashRequest: TrashRequest?
    @State private var trashReport: StorageTrashResult?

    private struct TrashRequest: Identifiable {
        let id = UUID()
        let entries: [StorageEntry]
    }

    private var isDark: Bool { colorScheme == .dark }
    private var palette: TreemapPalette { TreemapPalette(isDark: isDark) }
    private var current: FolderNode? { crumbs.last }
    private var collected: [StorageEntry] {
        collection.values.sorted { $0.bytes > $1.bytes }
    }
    private var collectedBytes: Int64 {
        collection.values.reduce(0) { $0 + $1.bytes }
    }

    var body: some View {
        PageScreen(
            scrolls: false,
            header: { pageHeader },
            subHeader: {
                StorageLocationBar(
                    pathNodes: crumbs,
                    volume: volume,
                    sizeBasis: model.treeSizeBasis,
                    onSelect: { index in
                        // `crumbs` starts at the tree root, so crumb `index` keeps its
                        // first `index + 1` entries.
                        crumbs = Array(crumbs.prefix(index + 1))
                        hovered = nil
                    })
                metricsRow
            },
            content: {
                // Scan progress and the trash report are page content, not chrome: the
                // bar slot carries the command bar and nothing else, like every other
                // destination.
                VStack(spacing: 0) {
                    bodyContent
                    if model.isScanning {
                        progressPanel
                    }
                    if let trashReport, !trashReport.moved.isEmpty || !trashReport.failed.isEmpty {
                        trashNotice(trashReport)
                    }
                }
            },
            bar: { commandBar }
        )
        .sheet(item: $trashRequest) { request in
            StorageTrashSheet(entries: request.entries, onConfirm: performTrash)
        }
        .task {
            volume = VolumeCapacity.current()
        }
        // The final trees replace the live render (same canvas, full data).
        .task(id: model.folderTrees) {
            guard !model.folderTrees.isEmpty else { return }
            let kids = model.folderTrees.sorted { $0.size > $1.size }
            let home = FolderNode(
                url: TestEnvironment.paths.root, size: kids.reduce(0) { $0 + $1.size },
                children: kids)
            finalHome = home
            tree = home
            crumbs = [home]
            hovered = nil
        }
        // Publish a throttled tree snapshot, re-resolving the crumbs and the hover into
        // it, so the canvas and the breadcrumb read one stable tree instead of every
        // rollup.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let newest = model.liveTree ?? finalHome else { continue }
                guard newest != tree else { continue }
                tree = newest
                crumbs = Self.reresolve(crumbs, into: newest)
                hovered = hovered.flatMap { Self.node(with: $0.url, in: newest) }
            }
        }
        .onChange(of: model.isScanning) { _, scanning in
            // A new scan can change every size; a collection from the old tree would
            // come back with numbers nothing measured.
            if scanning {
                collection.removeAll()
                trashReport = nil
            }
        }
        .onAppear {
            VerboseLog.event(.debug, .ui, .uiViewAppeared, .code(.view, .viewStorage))
        }
        .onChange(of: trashRequest?.id) { _, request in
            if request != nil {
                VerboseLog.event(.debug, .ui, .uiSheetPresented, .code(.sheet, .sheetTrash))
            }
        }
    }

    // MARK: - Header and metrics

    /// Nil before the first scan, so the page shows no number it cannot source.
    private var pageHeader: some View {
        PageHeader(
            title: "Storage",
            subtitle: "Where your space goes.",
            metric: current?.size.formatted(.byteCount(style: .file)),
            metricLabel: current == nil ? nil : "in this folder"
        )
        .accessibilityIdentifier("storage.header")
    }

    private var largeCategory: CategoryState? {
        model.categories.first { $0.id == "large-files" }
    }

    private var metricsRow: some View {
        let used = volume.map {
            Double($0.total - $0.free) / Double(max($0.total, 1))
        }
        return StorageMetricsRow(
            free: volume?.free,
            usedShare: used,
            cleanable: model.didFinishScan ? model.totalBytes : nil,
            largeFilesBytes: largeCategory?.bytes,
            largeFilesCount: largeCategory?.items.count,
            didFinishScan: model.didFinishScan,
            isScanning: model.isScanning,
            onScan: { model.scan() },
            onOpenFindings: { destination = "overview" },
            onOpenLargeFiles: {
                if largeCategory != nil { destination = "large-files" }
            }
        )
    }

    // MARK: - Body

    @ViewBuilder private var bodyContent: some View {
        if let current {
            HStack(alignment: .top, spacing: Spacing.s4) {
                canvas(current)
                StorageLedger(
                    folder: current,
                    palette: palette,
                    selected: Set(collection.keys),
                    hovered: hovered?.url,
                    isEnabled: !model.isScanning,
                    readErrors: model.readErrors,
                    onToggle: toggle,
                    onOpen: open,
                    onReveal: reveal)
            }
            .pageHorizontalPadding()
            .padding(.top, Spacing.s4)
            .padding(.bottom, Spacing.s3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else if !model.isScanning, !model.steps.isEmpty, model.folderTrees.isEmpty {
            EmptyStateView(
                title: "The scan did not produce a disk map.",
                message: "Folder measuring failed or the scan was stopped. Scan again to build it.",
                actionTitle: "Scan this Mac",
                action: { model.scan() }
            )
            .padding(Spacing.s8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !model.isScanning {
            EmptyStateView(
                title: "The disk map appears after a scan.",
                message: "Scan this Mac to see where the space goes.",
                actionTitle: "Scan this Mac",
                action: { model.scan() }
            )
            .padding(Spacing.s8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: Spacing.s2) {
                ActivitySpinner()
                Text("Measuring your folders")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func canvas(_ current: FolderNode) -> some View {
        TreemapCanvas(
            node: current,
            isDark: isDark,
            selected: Set(collection.keys),
            onHover: { hovered = $0 },
            onToggle: { toggle($0) },
            onOpen: { open($0) }
        )
        .overlay {
            // Direct labels on the top tier: the biggest folders read without hovering.
            // Coordinates are the canvas layout's own, top-left origin.
            GeometryReader { _ in
                ForEach(overlayLabels) { label in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(label.title)
                            .font(Typography.row)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if !label.subtitle.isEmpty {
                            Text(label.subtitle)
                                .font(Typography.caption)
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(label.darkText ? MapColors.labelDark : MapColors.labelLight)
                    .frame(maxWidth: max(0, label.rect.width - 12), alignment: .leading)
                    .offset(x: label.rect.minX + 6, y: label.rect.minY + 5)
                }
            }
            .allowsHitTesting(false)
        }
        .accessibilityLabel(
            "Storage map for \(current.url.lastPathComponent), "
                + current.size.formatted(.byteCount(style: .file))
        )
        .accessibilityHint("Click a block to open that folder. Check a row to collect it.")
        .clipShape(.rect(corners: .fixed(Metrics.panelRadius)))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: {
            canvasSize = $0
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
                .background(Theme.paperRaised, in: .rect(corners: .fixed(Metrics.controlRadius)))
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 1)
                }
                .padding(Spacing.s6)
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Collection

    private func toggle(_ node: FolderNode) {
        guard !model.isScanning else { return }
        if collection[node.url] != nil {
            collection[node.url] = nil
        } else {
            collection[node.url] = StorageEntry(url: node.url, bytes: node.size)
        }
    }

    private func open(_ node: FolderNode) {
        // The canvas reports the deepest tile under the pointer; a ledger row is already
        // a direct child. Both resolve onto the direct child of the rendered folder, the
        // same node the breadcrumb shows.
        guard let parent = crumbs.last,
            let child = Self.directChild(of: parent, containing: node), !child.children.isEmpty
        else { return }
        crumbs.append(child)
        hovered = nil
    }

    private func reveal(_ node: FolderNode) {
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }

    private func performTrash() {
        let policy = SafetyPolicy(
            home: TestEnvironment.paths.root,
            allowsOutsideHome: model.scanOutsideHome,
            excludedPaths: model.excludedPaths)
        let result = StorageTrasher(policy: policy, dryRun: DryRun.enabled, ledger: model.trashLedger)
            .trash(trashRequest?.entries ?? [])
        trashReport = result
        collection.removeAll()
        trashRequest = nil
    }

    private func trashNotice(_ result: StorageTrashResult) -> some View {
        var parts: [String] = []
        if !result.moved.isEmpty {
            parts.append("Moved \(result.moved.count) \(result.moved.count == 1 ? "item" : "items") to the Trash.")
        }
        if result.failed.count == 1, let failure = result.failed.first {
            parts.append("Could not move \(failure.name): \(failure.reason).")
        } else if !result.failed.isEmpty {
            parts.append("\(result.failed.count) could not be moved.")
        }
        if !result.moved.isEmpty {
            parts.append("Rescan to update the sizes.")
        }
        return StatusStrip(
            text: parts.joined(separator: " "),
            systemImage: result.failed.isEmpty ? "trash" : "exclamationmark.triangle",
            tone: result.failed.isEmpty ? .neutral : .amber,
            action: .init(
                title: "Scan again",
                perform: {
                    trashReport = nil
                    model.scan()
                }),
            dismiss: .init(label: "Dismiss", perform: { trashReport = nil })
        )
    }

    private var barDetail: String {
        if model.isScanning { return "Wait for the scan to finish." }
        let hint = "Click a block to open it. Check a row to collect it."
        if collection.isEmpty { return hint }
        let count = collection.count
        return "\(count) \(count == 1 ? "item" : "items") collected. " + hint
    }

    private var barReason: String? {
        if model.isScanning { return "Wait for the scan to finish." }
        if collection.isEmpty { return "Nothing collected." }
        return nil
    }

    private var commandBar: some View {
        CommandBar(
            metric: collectedBytes.formatted(.byteCount(style: .file)),
            detail: barDetail,
            actionTitle: "Move to Trash...",
            // Under the dry-run gate the sheet opens as a preview and its confirm button
            // stays disabled, so the user can still see what would move.
            isEnabled: !collection.isEmpty && !model.isScanning,
            isDestructive: true,
            secondaryTitle: "Clear",
            secondaryAction: { collection.removeAll() },
            isSecondaryEnabled: !collection.isEmpty,
            help: "Move the collected folders to the Trash.",
            accessibilityLabel: "Move \(collection.count) "
                + "\(collection.count == 1 ? "item" : "items") to the Trash",
            disabledReason: barReason,
            primaryIdentifier: "storage.trash",
            secondaryIdentifier: "storage.clear",
            action: { trashRequest = TrashRequest(entries: collected) })
    }

    // MARK: - Navigation

    /// The newest node with this URL, or nil when the update dropped it.
    private static func node(with url: URL, in tree: FolderNode) -> FolderNode? {
        if tree.url == url { return tree }
        for child in tree.children {
            if let hit = node(with: url, in: child) { return hit }
        }
        return nil
    }

    /// The old path carried into `tree`: keep the crumbs that still resolve, by URL,
    /// and truncate at the first one the new snapshot dropped.
    private static func reresolve(_ crumbs: [FolderNode], into tree: FolderNode) -> [FolderNode] {
        guard !crumbs.isEmpty else { return [tree] }
        var node = tree
        var out = [node]
        for crumb in crumbs.dropFirst() {
            guard let next = node.children.first(where: { $0.url == crumb.url }) else { break }
            out.append(next)
            node = next
        }
        return out
    }

    /// The direct child of the shown folder that contains `node`. A click on a nested
    /// block resolves to its top-level parent, which is the row the ledger shows.
    static func directChild(of parent: FolderNode, containing node: FolderNode) -> FolderNode? {
        parent.children.first { child in
            child.url == node.url || node.url.path.hasPrefix(child.url.path + "/")
        }
    }

    /// Names for the top-tier blocks, from the same layout function the Metal tiles use
    /// and the same canvas size, so a label cannot outlive the tile it names.
    private var overlayLabels: [TreemapLabel] {
        guard let node = crumbs.last, canvasSize.width > 0, canvasSize.height > 0 else { return [] }
        return TreemapMTKView.labels(for: node, in: CGRect(origin: .zero, size: canvasSize), palette: palette)
    }

    // MARK: - Scan progress

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
                            Text("\(snap.files) files · \(snap.bytes.formatted(.byteCount(style: .file)))")
                                .font(Typography.caption)
                                .monospacedDigit()
                                .foregroundStyle(Theme.inkSecondary)
                        }
                    } else {
                        ActivitySpinner()
                        Text(model.currentStep.map { ScanStepCopy.title($0) } ?? "Starting scan")
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
                }
                HStack(spacing: Spacing.s2) {
                    Spacer()
                    SecondaryActionButton(
                        title: "Pause", isEnabled: !model.isPaused,
                        action: { model.togglePause() }
                    )
                    .accessibilityIdentifier("storage.pause")
                    SecondaryActionButton(
                        title: "Resume", isEnabled: model.isPaused,
                        action: { model.togglePause() }
                    )
                    .accessibilityIdentifier("storage.resume")
                }
            }
            .pageHorizontalPadding()
            .padding(.vertical, Spacing.s2)
        }
    }

    /// "<phase title>" plus its fraction when the phase knows one.
    private func headline(_ activity: ScanActivity) -> String {
        var parts = [ScanStepCopy.title(activity.phase)]
        if activity.total > activity.done, activity.total > 0 {
            parts.append("\(activity.done) of \(activity.total)")
        }
        if model.isPaused { parts.append("paused") }
        return parts.joined(separator: " · ")
    }
}

struct TreemapCanvas: NSViewRepresentable {
    let node: FolderNode
    let isDark: Bool
    let selected: Set<URL>
    let onHover: (FolderNode?) -> Void
    let onToggle: (FolderNode) -> Void
    let onOpen: (FolderNode) -> Void

    func makeNSView(context: Context) -> TreemapMTKView {
        let view = TreemapMTKView(frame: .zero, device: GPUContext.shared?.device)
        view.isDark = isDark
        view.configure()
        return view
    }

    func updateNSView(_ view: TreemapMTKView, context: Context) {
        view.onHover = onHover
        view.onToggle = onToggle
        view.onOpen = onOpen
        let appearanceChanged = view.isDark != isDark
        view.isDark = isDark
        // FolderNode is Equatable: relayout on any structural change (sizes grow live
        // during a scan even though the URL stays the same).
        if view.node != node || appearanceChanged {
            view.node = node
            view.selected = selected
            view.relayout()
        } else {
            view.selected = selected
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

/// A name and byte count drawn directly on a block.
struct TreemapLabel: Identifiable {
    let rect: CGRect
    let title: String
    let subtitle: String
    let darkText: Bool
    var id: CGRect { rect }
}

final class TreemapMTKView: MTKView, MTKViewDelegate {
    var node: FolderNode?
    var isDark = false
    /// Direct children currently in the collection.
    var selected: Set<URL> = [] {
        didSet { if selected != oldValue { rebuildInstances() } }
    }
    var onHover: (FolderNode?) -> Void = { _ in }
    /// Collects the top-level child under the pointer, from the context menu.
    var onToggle: (FolderNode) -> Void = { _ in }
    /// A click opens the folder of the deepest tile under the pointer; DiskMapView
    /// resolves it to the direct child of the rendered folder.
    var onOpen: (FolderNode) -> Void = { _ in }
    private var tiles: [TreemapTile] = []
    private var instances: MTLBuffer?
    private var pipeline: MTLRenderPipelineState?
    private var hoveredURL: URL?

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
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Storage map")
        setAccessibilityIdentifier("storage.canvas")
    }

    func relayout() {
        guard let node, bounds.width > 0, bounds.height > 0 else { return }
        let palette = TreemapPalette(isDark: isDark)
        tiles = Self.tiles(for: node, in: CGRect(origin: .zero, size: bounds.size), palette: palette)
        rebuildInstances(palette: palette)
    }

    private func rebuildInstances(palette supplied: TreemapPalette? = nil) {
        guard let device, bounds.width > 0, bounds.height > 0, !tiles.isEmpty else {
            instances = nil
            needsDisplay = true
            return
        }
        let palette = supplied ?? TreemapPalette(isDark: isDark)
        var data: [SIMD4<Float>] = []
        for tile in tiles {
            let r = tile.rect
            data.append(
                SIMD4(
                    Float(r.minX / bounds.width), Float(r.minY / bounds.height), Float(r.width / bounds.width),
                    Float(r.height / bounds.height)))
            data.append(tile.color)
            if selected.contains(tile.node.url) {
                data.append(palette.accentBorder)
            } else if hoveredURL == tile.node.url {
                data.append(palette.hoverBorder)
            } else {
                data.append(palette.border)
            }
        }
        instances =
            data.isEmpty ? nil : device.makeBuffer(bytes: data, length: data.count * MemoryLayout<SIMD4<Float>>.stride)
        needsDisplay = true
    }

    /// Labels for top-level children big enough to carry text (44 x 36 pt). Shares mirror
    /// `tiles(for:in:level:)`, so label rects match the canvas.
    static func labels(for node: FolderNode, in bounds: CGRect, palette: TreemapPalette) -> [TreemapLabel] {
        guard !node.children.isEmpty, bounds.width > 0 else { return [] }
        let boundsArea = bounds.width * bounds.height
        var out: [TreemapLabel] = []
        for item in Treemap.layout(node.children.map(\.size), in: bounds)
        where item.rect.width >= 44 && item.rect.height >= 36 {
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
                    subtitle: item.rect.height >= 54 && item.rect.width >= 64
                        ? child.size.formatted(.byteCount(style: .file)) : "",
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
        var out = [TreemapTile(rect: bounds, color: palette.background, node: node)]
        let rects = Treemap.layout(node.children.map(\.size), in: bounds)
        let boundsArea = bounds.width * bounds.height
        for item in rects where item.rect.width > 4 && item.rect.height > 4 {
            let child = node.children[item.index]
            let inner = item.rect.insetBy(dx: 1, dy: 1)
            let share = boundsArea > 0 ? item.rect.width * item.rect.height / boundsArea : 0
            out.append(
                TreemapTile(rect: inner, color: palette.rampShare(share), node: child))
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
        hoveredURL = nil
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

    /// The direct child of the shown folder that contains `node`. A click on a nested
    /// block collects its top-level parent, which is the row the ledger shows.
    private func directChild(containing node: FolderNode) -> FolderNode? {
        guard let root = self.node else { return nil }
        return DiskMapView.directChild(of: root, containing: node)
    }

    override func mouseMoved(with event: NSEvent) {
        let hit = tile(at: convert(event.locationInWindow, from: nil))?.node
        onHover(hit)
        if hit?.url != hoveredURL {
            hoveredURL = hit?.url
            rebuildInstances()
        }
    }

    override func mouseExited(with event: NSEvent) {
        onHover(nil)
        if hoveredURL != nil {
            hoveredURL = nil
            rebuildInstances()
        }
    }

    /// The last open, so the second click of a double click cannot drill another level
    /// in the folder that just appeared.
    private var lastOpen = Date.distantPast

    override func mouseDown(with event: NSEvent) {
        // One click opens; the guard keeps the second click of a double click from
        // drilling another level in the folder that just appeared.
        guard event.clickCount == 1,
            let hit = tile(at: convert(event.locationInWindow, from: nil))?.node
        else { return }
        let now = Date()
        guard now.timeIntervalSince(lastOpen) > 0.3 else { return }
        lastOpen = now
        onOpen(hit)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let hit = tile(at: convert(event.locationInWindow, from: nil))?.node,
            let child = directChild(containing: hit)
        else { return nil }
        let menu = NSMenu()
        let collect = NSMenuItem(
            title: selected.contains(child.url)
                ? "Remove from collection" : "Collect \(child.url.lastPathComponent)",
            action: #selector(toggleFromMenu(_:)), keyEquivalent: "")
        collect.representedObject = child
        collect.target = self
        menu.addItem(collect)
        menu.addItem(.separator())
        let reveal = NSMenuItem(title: "Reveal in Finder", action: #selector(reveal(_:)), keyEquivalent: "")
        reveal.representedObject = child.url
        reveal.target = self
        menu.addItem(reveal)
        return menu
    }

    @objc private func toggleFromMenu(_ sender: NSMenuItem) {
        if let node = sender.representedObject as? FolderNode { onToggle(node) }
    }

    @objc private func reveal(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
}
