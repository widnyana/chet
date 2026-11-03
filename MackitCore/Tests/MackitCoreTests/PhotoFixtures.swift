import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Deterministic test images: a 16x16 grid of random gray blocks from a seed.
enum PhotoFixtures {
    static func blocks(seed: UInt64, size: Int = 512) -> CGImage {
        var state = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let context = makeContext(size)
        let cell = CGFloat(size) / 16
        for y in 0..<16 {
            for x in 0..<16 {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                let gray = CGFloat((state >> 33) % 256) / 255
                context.setFillColor(CGColor(red: gray, green: gray, blue: gray, alpha: 1))
                context.fill(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell))
            }
        }
        return context.makeImage()!
    }

    /// The same image squeezed to 32x32 and scaled back up: a strongly blurred copy.
    static func blurred(_ image: CGImage) -> CGImage {
        resized(resized(image, to: 32), to: image.width)
    }

    static func resized(_ image: CGImage, to size: Int) -> CGImage {
        let context = makeContext(size)
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

    private static func makeContext(_ size: Int) -> CGContext {
        CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }
}
