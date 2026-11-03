import CoreGraphics
import Metal
import Testing

@testable import MackitCore

struct TreemapTests {
    let bounds = CGRect(x: 0, y: 0, width: 800, height: 500)
    let sizes: [Int64] = [600, 300, 200, 120, 80, 50, 30, 10, 5, 5]

    @Test func rectsTileTheWholeAreaWithoutOverlap() {
        let rects = Treemap.layout(sizes, in: bounds)
        #expect(rects.count == sizes.count)
        let area = rects.reduce(0.0) { $0 + Double($1.rect.width * $1.rect.height) }
        #expect(abs(area - Double(bounds.width * bounds.height)) < 0.01)
        for (i, a) in rects.enumerated() {
            #expect(bounds.insetBy(dx: -0.001, dy: -0.001).contains(a.rect))
            for b in rects[(i + 1)...] {
                let overlap = a.rect.intersection(b.rect)
                #expect(overlap.isNull || overlap.width * overlap.height < 0.001)
            }
        }
    }

    @Test func areaIsProportionalToSize() {
        let total = Double(sizes.reduce(0, +))
        let full = Double(bounds.width * bounds.height)
        for item in Treemap.layout(sizes, in: bounds) {
            let share = Double(item.rect.width * item.rect.height) / full
            let expected = Double(sizes[item.index]) / total
            #expect(abs(share - expected) <= expected * 0.01)
        }
    }

    @Test func zeroSizesGetNoRect() {
        let rects = Treemap.layout([10, 0, 5], in: bounds)
        #expect(Set(rects.map(\.index)) == [0, 2])
    }

    @Test func hitTestFindsRectAtItsCenter() {
        for item in Treemap.layout(sizes, in: bounds) {
            #expect(
                Treemap.hitTest(Treemap.layout(sizes, in: bounds), CGPoint(x: item.rect.midX, y: item.rect.midY))
                    == item.index)
        }
        #expect(Treemap.hitTest([], CGPoint(x: 1, y: 1)) == nil)
    }

    @Test func treemapShadersCompileIntoRenderPipeline() throws {
        let gpu = try GPUContext()
        _ = try gpu.renderPipeline(vertex: "treemap_vertex", fragment: "treemap_fragment", pixelFormat: .bgra8Unorm)
    }
}
