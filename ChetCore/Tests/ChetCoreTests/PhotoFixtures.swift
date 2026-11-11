import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Deterministic test images: a 16x16 grid of random gray blocks from a seed.
enum PhotoFixtures {
    static func blocks(seed: UInt64, size: Int = 512) -> CGImage {
        blocks(seed: seed, width: size, height: size)
    }

    /// The same 16x16 block grid over a canvas of any shape.
    static func blocks(seed: UInt64, width: Int, height: Int) -> CGImage {
        let context = makeContext(width: width, height: height)
        drawBlocks(seed, in: CGRect(x: 0, y: 0, width: width, height: height), context)
        return context.makeImage()!
    }

    /// The block grid at a random per-cell opacity: alpha varies over the whole canvas.
    static func transparentBlocks(seed: UInt64, size: Int = 512) -> CGImage {
        let context = makeContext(width: size, height: size)
        let box = CGRect(x: 0, y: 0, width: size, height: size)
        context.clear(box)
        drawBlocks(seed, in: box, context) { x, y in
            CGFloat((seed &+ UInt64(y * 16 + x)) &* 2_654_435_761 >> 24 & 0xFF) / 255
        }
        return context.makeImage()!
    }

    /// `image` composited over an opaque color of the same size.
    static func onBackground(_ image: CGImage, _ color: CGColor) -> CGImage {
        let context = makeContext(width: image.width, height: image.height)
        let box = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(color)
        context.fill(box)
        context.draw(image, in: box)
        return context.makeImage()!
    }

    /// The same image squeezed to 32x32 and scaled back up: a strongly blurred copy.
    static func blurred(_ image: CGImage) -> CGImage {
        resized(resized(image, to: 32), to: image.width)
    }

    static func resized(_ image: CGImage, to size: Int) -> CGImage {
        let context = makeContext(width: size, height: size)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        return context.makeImage()!
    }

    @discardableResult
    static func write(_ image: CGImage, to url: URL, type: UTType = .png, quality: Double = 0.85) -> URL {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(
            destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        CGImageDestinationFinalize(destination)
        return url
    }

    private static func drawBlocks(
        _ seed: UInt64, in rect: CGRect, _ context: CGContext, alpha: (Int, Int) -> CGFloat = { _, _ in 1 }
    ) {
        var state = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let cell = rect.width / 16
        let cellHeight = rect.height / 16
        for y in 0..<16 {
            for x in 0..<16 {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                let gray = CGFloat((state >> 33) % 256) / 255
                context.setFillColor(CGColor(red: gray, green: gray, blue: gray, alpha: alpha(x, y)))
                context.fill(
                    CGRect(
                        x: rect.minX + CGFloat(x) * cell, y: rect.minY + CGFloat(y) * cellHeight,
                        width: cell, height: cellHeight))
            }
        }
    }

    private static func makeContext(width: Int, height: Int) -> CGContext {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }
}
