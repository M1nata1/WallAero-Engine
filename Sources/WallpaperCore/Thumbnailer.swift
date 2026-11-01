import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum Thumbnailer {
    public static let defaultMaxPixelSize = 480

    /// First frame of an image file, downsampled and with EXIF orientation applied.
    public static func image(at url: URL, maxPixelSize: Int = defaultMaxPixelSize) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return image(from: source, frame: 0, maxPixelSize: maxPixelSize)
    }

    /// The first frame of an image file that is not black, or the first if all of them are: an
    /// animated one may fade in.
    public static func lightImage(at url: URL, maxPixelSize: Int = defaultMaxPixelSize) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        let frames = [0, count / 4, count / 2, count * 3 / 4].compactMap { image(from: source, frame: $0, maxPixelSize: maxPixelSize) }
        return frames.first { !isNearlyBlack($0) } ?? frames.first
    }

    private static func image(from source: CGImageSource, frame: Int, maxPixelSize: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, frame, options as CFDictionary)
    }

    /// How light a picture is on the whole, from 0 to 1.
    public static func brightness(of image: CGImage) -> Double {
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return 0 }
        var sum = 0.0
        for pixel in stride(from: 0, to: pixels.count, by: 4) {
            sum += 0.3 * Double(pixels[pixel]) + 0.6 * Double(pixels[pixel + 1]) + 0.1 * Double(pixels[pixel + 2])
        }
        return sum / Double(side * side) / 255
    }

    /// Dark enough to say nothing of the wallpaper in the library: a scene caught before it has
    /// come up, or a video that starts from black.
    public static func isNearlyBlack(_ image: CGImage) -> Bool {
        brightness(of: image) < 0.05
    }

    /// A representative frame of a video. `maxPixelSize` of nil keeps the full resolution.
    static func frame(ofVideoAt url: URL, at seconds: Double, maxPixelSize: Int? = defaultMaxPixelSize) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        if let maxPixelSize {
            generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        }
        let (image, _) = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
        return image
    }

    /// A frame of a video early on that is not black, or the first looked at if all of them are.
    static func lightFrame(ofVideoAt url: URL, duration: Double) async -> CGImage? {
        var first: CGImage?
        for seconds in [min(duration * 0.1, 2), duration * 0.25, duration * 0.5, duration * 0.75] {
            guard let frame = try? await frame(ofVideoAt: url, at: seconds) else { continue }
            if !isNearlyBlack(frame) { return frame }
            first = first ?? frame
        }
        return first
    }

    /// Keeps every pixel as it is, see-through ones too: for pictures a scene is put together from.
    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ImportError.conversionFailed("Cannot create \(url.lastPathComponent).")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ImportError.conversionFailed("Cannot write \(url.lastPathComponent).")
        }
    }

    public static func writeJPEG(_ image: CGImage, to url: URL, quality: Double = 0.85) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ImportError.conversionFailed("Cannot create \(url.lastPathComponent).")
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ImportError.conversionFailed("Cannot write \(url.lastPathComponent).")
        }
    }
}
