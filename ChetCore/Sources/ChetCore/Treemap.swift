import CoreGraphics

public struct TreemapRect: Sendable, Equatable {
    /// Index into the sizes passed to `layout`.
    public let index: Int
    public let rect: CGRect
}

/// Squarified treemap (Bruls, Huizing, van Wijk): rectangles close to square, area proportional to size.
public enum Treemap {
    public static func layout(_ sizes: [Int64], in bounds: CGRect) -> [TreemapRect] {
        let items = sizes.enumerated().filter { $0.element > 0 }.sorted { $0.element > $1.element }
        let total = items.reduce(0.0) { $0 + Double($1.element) }
        guard total > 0, bounds.width > 0, bounds.height > 0 else { return [] }
        let scale = Double(bounds.width * bounds.height) / total
        let areas = items.map { (index: $0.offset, area: Double($0.element) * scale) }
        var result: [TreemapRect] = []
        var free = bounds
        var row: [(index: Int, area: Double)] = []

        func worst(_ row: [(index: Int, area: Double)], _ side: Double) -> Double {
            let sum = row.reduce(0) { $0 + $1.area }
            guard let largest = row.map(\.area).max(), let smallest = row.map(\.area).min(), sum > 0 else {
                return .infinity
            }
            return max(side * side * largest / (sum * sum), sum * sum / (side * side * smallest))
        }

        func place(_ row: [(index: Int, area: Double)]) {
            let sum = row.reduce(0) { $0 + $1.area }
            if free.width >= free.height {
                let width = sum / Double(free.height)
                var y = Double(free.minY)
                for item in row {
                    let height = item.area / width
                    result.append(
                        TreemapRect(index: item.index, rect: CGRect(x: free.minX, y: y, width: width, height: height)))
                    y += height
                }
                free = CGRect(x: free.minX + width, y: free.minY, width: free.width - width, height: free.height)
            } else {
                let height = sum / Double(free.width)
                var x = Double(free.minX)
                for item in row {
                    let width = item.area / height
                    result.append(
                        TreemapRect(index: item.index, rect: CGRect(x: x, y: free.minY, width: width, height: height)))
                    x += width
                }
                free = CGRect(x: free.minX, y: free.minY + height, width: free.width, height: free.height - height)
            }
        }

        for item in areas {
            let side = Double(min(free.width, free.height))
            if row.isEmpty || worst(row + [item], side) <= worst(row, side) {
                row.append(item)
            } else {
                place(row)
                row = [item]
            }
        }
        if !row.isEmpty { place(row) }
        return result
    }

    public static func hitTest(_ rects: [TreemapRect], _ point: CGPoint) -> Int? {
        rects.last { $0.rect.contains(point) }?.index
    }
}
