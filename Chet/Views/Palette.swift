import AppKit
import SwiftUI

// MARK: - Colour tokens

/// Every colour value in the app lives here. A view reads a token or a `MapColors`
/// ramp value; it never builds a colour from a literal.
enum Theme {
    static let paper = dynamic(
        light: NSColor(srgbRed: 0.965, green: 0.957, blue: 0.937, alpha: 1),
        dark: NSColor(srgbRed: 0.071, green: 0.075, blue: 0.086, alpha: 1))
    static let paperRaised = dynamic(
        light: NSColor(srgbRed: 0.988, green: 0.984, blue: 0.973, alpha: 1),
        dark: NSColor(srgbRed: 0.098, green: 0.106, blue: 0.118, alpha: 1))
    static let ink = dynamic(
        light: NSColor(srgbRed: 0.106, green: 0.110, blue: 0.118, alpha: 1),
        dark: NSColor(srgbRed: 0.949, green: 0.941, blue: 0.918, alpha: 1))
    static let inkSecondary = dynamic(
        light: NSColor(srgbRed: 0.388, green: 0.388, blue: 0.373, alpha: 1),
        dark: NSColor(srgbRed: 0.639, green: 0.631, blue: 0.604, alpha: 1))
    static let inkTertiary = dynamic(
        light: NSColor(srgbRed: 0.545, green: 0.541, blue: 0.514, alpha: 1),
        dark: NSColor(srgbRed: 0.455, green: 0.455, blue: 0.435, alpha: 1))
    static let hairline = dynamic(
        light: NSColor(srgbRed: 0.867, green: 0.851, blue: 0.816, alpha: 1),
        dark: NSColor(srgbRed: 0.173, green: 0.180, blue: 0.196, alpha: 1))
    static let accent = dynamic(
        light: NSColor(srgbRed: 0.141, green: 0.298, blue: 0.604, alpha: 1),
        dark: NSColor(srgbRed: 0.561, green: 0.659, blue: 0.910, alpha: 1))
    static let accentSoft = dynamic(
        light: NSColor(srgbRed: 0.910, green: 0.929, blue: 0.973, alpha: 1),
        dark: NSColor(srgbRed: 0.106, green: 0.141, blue: 0.212, alpha: 1))
    static let onAccent = dynamic(
        light: NSColor.white,
        dark: NSColor(srgbRed: 0.063, green: 0.067, blue: 0.078, alpha: 1))
    static let amber = dynamic(
        light: NSColor(srgbRed: 0.604, green: 0.357, blue: 0.000, alpha: 1),
        dark: NSColor(srgbRed: 0.878, green: 0.643, blue: 0.345, alpha: 1))
    static let red = dynamic(
        light: NSColor(srgbRed: 0.639, green: 0.137, blue: 0.106, alpha: 1),
        dark: NSColor(srgbRed: 0.941, green: 0.541, blue: 0.510, alpha: 1))
    static let capacityUsed = dynamic(
        light: NSColor(srgbRed: 0.839, green: 0.824, blue: 0.784, alpha: 1),
        dark: NSColor(srgbRed: 0.227, green: 0.235, blue: 0.255, alpha: 1))
    static let capacityFree = dynamic(
        light: NSColor(srgbRed: 0.914, green: 0.902, blue: 0.871, alpha: 1),
        dark: NSColor(srgbRed: 0.133, green: 0.141, blue: 0.157, alpha: 1))

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            })
    }
}

/// Label colours for text painted on the treemap blocks.
enum MapColors {
    static let labelDark = Color(red: 0.07, green: 0.08, blue: 0.09)
    static let labelLight = Color.white
}

// MARK: - Treemap ramp

/// One neutral ramp, read in one direction per appearance. Small blocks sit near
/// the paper, large blocks sit near the ink. The Metal canvas and the SwiftUI
/// swatch read the same endpoints, so a tile and its ledger row cannot drift.
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

    /// The ramp at a raw position, for legends and swatches.
    func color(_ t: CGFloat) -> Color {
        color(ramp(t))
    }

    /// The ramp colour of a block whose area share is `share`. The ledger swatch
    /// uses this exact call with the same share the canvas lays out.
    func colorShare(_ share: CGFloat) -> Color {
        color(rampShare(share))
    }

    private func color(_ value: SIMD4<Float>) -> Color {
        Color(.sRGB, red: Double(value.x), green: Double(value.y), blue: Double(value.z), opacity: 1)
    }
}
