import Compression
import CoreGraphics
import Foundation
import ImageIO

/// A picture of one of Wallpaper Engine's own scenes: a `.tex` file. Inside are the picture at
/// full size and smaller copies of it for drawing it small; only the full one is read.
///
/// The picture sits in the corner of a canvas with sides that are powers of two, as graphics
/// cards like them, so it is cut out of that. Its pixels are stored plainly, packed the way
/// graphics cards unpack them (DXT), or as a whole PNG or JPEG file, and may be compressed
/// with LZ4 on top.
enum WallpaperEngineTexture {
    /// The longest side read. Larger than any wallpaper, and it bounds the memory a file that
    /// lies about its size can ask for.
    static let longestSide = 16384

    private enum Format: Int {
        case rgba8888 = 0, dxt5 = 4, dxt3 = 6, dxt1 = 7, rg88 = 8, r8 = 9
    }

    /// What the pixels of a texture stand for. A scene's shaders are written knowing it.
    enum Channels: String {
        /// Red, green, blue and opacity.
        case color = "rgba"
        /// One value a pixel, in the red channel: a mask.
        case single = "r8"
        /// Two values a pixel, in red and green: a direction, or a shade of grey and its opacity.
        case double = "rg88"
    }

    /// One picture of a texture that holds several, or a part of one: a frame of an animation.
    struct Frame: Equatable {
        /// Which of the texture's pictures the frame is in.
        var picture: Int
        /// How long it is shown, in seconds.
        var duration: Double
        /// Where in that picture it is, in pixels; the two sides of it are given as vectors,
        /// so that a frame may lie turned on its side.
        var x: Double, y: Double
        var width: Double, widthY: Double
        var heightX: Double, height: Double
    }

    /// A texture read.
    struct Texture {
        /// Its pictures, cut out of their canvases: one, or the sheets of an animation.
        var pictures: [Picture]
        var channels: Channels
        /// Whether the picture ends at its edges rather than repeating, and whether it is drawn
        /// smoothed when stretched.
        var isClamped: Bool
        var isSmooth: Bool
        var frames: [Frame]
    }

    struct Picture {
        var image: CGImage
        /// The PNG or JPEG file the texture held, when it held one of the very picture: it
        /// can be written out as it is, which loses nothing and takes no time.
        var file: (data: Data, fileExtension: String)?
    }

    /// The full-size picture of a texture; all a still wallpaper needs of it.
    static func image(from data: Data) -> CGImage? {
        texture(from: data, onlyFirstPicture: true)?.pictures.first?.image
    }

    static func texture(from data: Data, onlyFirstPicture: Bool = false) -> Texture? {
        var reader = BinaryReader(data)
        guard reader.textToZero()?.hasPrefix("TEXV") == true, reader.textToZero()?.hasPrefix("TEXI") == true,
              let format = reader.int32(), let flags = reader.int32(),
              let canvasWidth = reader.int32(), let canvasHeight = reader.int32(),
              let width = reader.int32(), let height = reader.int32(), reader.uint32() != nil,
              let container = reader.textToZero(), container.hasPrefix("TEXB"),
              let version = Int(container.dropFirst(4)), (1...4).contains(version),
              let imageCount = reader.int32(), (1...4096).contains(imageCount)
        else {
            return nil
        }
        // From the third version on the pixels may be a picture file of a usual kind; which,
        // the file says by a number, and −1 stands for "none, plain pixels".
        var isPictureFile = false
        if version >= 3 {
            guard let kind = reader.int32() else { return nil }
            isPictureFile = kind != -1
        }
        if version >= 4 {
            // A video in place of a picture is not read.
            guard let isVideo = reader.int32(), isVideo == 0 else { return nil }
        }
        let sides = 1...longestSide
        var pictures: [Picture] = []
        for index in 0..<imageCount {
            guard let mipmapCount = reader.int32(), (1...64).contains(mipmapCount) else { return nil }
            for mipmap in 0..<mipmapCount {
                if version >= 4 {
                    // Three more fields before each picture: two numbers, a text, a number.
                    guard reader.int32() != nil, reader.int32() != nil, reader.text() != nil, reader.int32() != nil else { return nil }
                }
                guard let storedWidth = reader.int32(), let storedHeight = reader.int32() else { return nil }
                var isCompressed = false
                var unpackedSize = 0
                if version >= 2 {
                    guard let flag = reader.int32(), let size = reader.int32() else { return nil }
                    isCompressed = flag == 1
                    unpackedSize = size
                }
                guard let storedSize = reader.int32(), storedSize >= 0 else { return nil }
                // Only the full-size picture is wanted; the smaller copies after it are passed over.
                guard mipmap == 0, !(onlyFirstPicture && index > 0) else {
                    guard reader.skip(storedSize) else { return nil }
                    continue
                }
                guard var pixels = reader.bytes(storedSize), sides.contains(storedWidth), sides.contains(storedHeight) else { return nil }
                if isCompressed {
                    guard unpackedSize > 0, unpackedSize <= storedWidth * storedHeight * 4 || isPictureFile,
                          unpackedSize <= longestSide * longestSide * 4,
                          let unpacked = unpackedLZ4(pixels, size: unpackedSize)
                    else {
                        return nil
                    }
                    pixels = unpacked
                }

                let whole: CGImage?
                if isPictureFile {
                    whole = CGImageSourceCreateWithData(pixels as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
                } else {
                    guard let format = Format(rawValue: format),
                          let rgba = rgba(from: pixels, format: format, width: storedWidth, height: storedHeight)
                    else {
                        return nil
                    }
                    whole = cgImage(rgba: rgba, width: storedWidth, height: storedHeight)
                }
                guard let whole else { return nil }
                // The picture itself is the top left part of the canvas. The sizes the file gives
                // are those of the first picture; they hold for this one as long as it is as
                // large as the canvas.
                if index == 0, sides.contains(width), sides.contains(height),
                   whole.width == canvasWidth, whole.height == canvasHeight,
                   width <= whole.width, height <= whole.height, width != whole.width || height != whole.height,
                   let cut = whole.cropping(to: CGRect(x: 0, y: 0, width: width, height: height)) {
                    pictures.append(Picture(image: cut, file: nil))
                } else {
                    pictures.append(Picture(image: whole, file: isPictureFile ? fileKind(of: pixels).map { (pixels, $0) } : nil))
                }
            }
            if onlyFirstPicture { break }
        }
        guard !pictures.isEmpty else { return nil }
        let channels: Channels
        switch Format(rawValue: format) {
        case .r8 where !isPictureFile: channels = .single
        case .rg88 where !isPictureFile: channels = .double
        default: channels = .color
        }
        // Bits of the flags: 1 for "not smoothed", 2 for "ends at its edges", 4 for an animation.
        return Texture(pictures: pictures, channels: channels, isClamped: flags & 2 != 0, isSmooth: flags & 1 == 0,
                       frames: onlyFirstPicture ? [] : frames(&reader, pictureCount: pictures.count))
    }

    /// The frames of an animated texture, which follow its pictures; none if it has none or
    /// they cannot be read.
    private static func frames(_ reader: inout BinaryReader, pictureCount: Int) -> [Frame] {
        guard !reader.isAtEnd, let mark = reader.textToZero(), mark.hasPrefix("TEXS"), let version = Int(mark.dropFirst(4)),
              let count = reader.int32(), (1...100_000).contains(count)
        else {
            return []
        }
        if version >= 3 {
            // The size of the whole animation; the frames say the same.
            guard reader.int32() != nil, reader.int32() != nil else { return [] }
        }
        var frames: [Frame] = []
        for _ in 0..<count {
            guard let picture = reader.int32(), let duration = reader.float() else { return [] }
            var numbers: [Double] = []
            for _ in 0..<6 {
                // The first version wrote whole numbers, the later ones fractions.
                guard let number = version == 1 ? reader.int32().map(Double.init) : reader.float() else { return [] }
                numbers.append(number)
            }
            guard (0..<pictureCount).contains(picture), duration.isFinite, numbers.allSatisfy(\.isFinite) else { return [] }
            frames.append(Frame(picture: picture, duration: duration, x: numbers[0], y: numbers[1], width: numbers[2],
                                widthY: numbers[3], heightX: numbers[4], height: numbers[5]))
        }
        return frames
    }

    /// Whether the bytes are a PNG or a JPEG file, by how they begin.
    private static func fileKind(of data: Data) -> String? {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        return nil
    }

    // MARK: - Pixels

    /// Unpacks one block of LZ4, the compression the textures use.
    static func unpackedLZ4(_ packed: Data, size: Int) -> Data? {
        guard size > 0, !packed.isEmpty else { return nil }
        var unpacked = Data(count: size)
        let written = unpacked.withUnsafeMutableBytes { target in
            packed.withUnsafeBytes { source in
                compression_decode_buffer(target.bindMemory(to: UInt8.self).baseAddress!, size,
                                          source.bindMemory(to: UInt8.self).baseAddress!, packed.count,
                                          nil, COMPRESSION_LZ4_RAW)
            }
        }
        return written == size ? unpacked : nil
    }

    /// The pixels as four bytes each — red, green, blue, opacity — whatever form they came in.
    static func rgba(from pixels: Data, format: Int, width: Int, height: Int) -> Data? {
        Format(rawValue: format).flatMap { rgba(from: pixels, format: $0, width: width, height: height) }
    }

    private static func rgba(from pixels: Data, format: Format, width: Int, height: Int) -> Data? {
        let count = width * height
        switch format {
        case .rgba8888:
            return pixels.count >= count * 4 ? pixels.prefix(count * 4) : nil
        case .r8:
            // One byte a pixel: a shade of grey.
            guard pixels.count >= count else { return nil }
            var rgba = Data(capacity: count * 4)
            for value in pixels.prefix(count) {
                rgba.append(contentsOf: [value, value, value, 255])
            }
            return rgba
        case .rg88:
            // Two bytes a pixel, kept as red and green: a scene's shaders read them so.
            guard pixels.count >= count * 2 else { return nil }
            var rgba = Data(capacity: count * 4)
            pixels.withUnsafeBytes { (source: UnsafeRawBufferPointer) in
                for index in 0..<count {
                    rgba.append(contentsOf: [source[index * 2], source[index * 2 + 1], 0, 255])
                }
            }
            return rgba
        case .dxt1, .dxt3, .dxt5:
            return unpackedDXT(pixels, format: format, width: width, height: height)
        }
    }

    /// DXT keeps a picture as squares of four by four pixels. Each square has two colors, the
    /// two between them worked out from those, and for every pixel which of the four it is.
    /// DXT3 and DXT5 add the opacity of the pixels in eight bytes before that.
    private static func unpackedDXT(_ packed: Data, format: Format, width: Int, height: Int) -> Data? {
        let blockSize = format == .dxt1 ? 8 : 16
        let across = (width + 3) / 4, down = (height + 3) / 4
        guard packed.count >= across * down * blockSize else { return nil }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        packed.withUnsafeBytes { (source: UnsafeRawBufferPointer) in
            for blockY in 0..<down {
                for blockX in 0..<across {
                    var at = (blockY * across + blockX) * blockSize
                    var alpha = [UInt8](repeating: 255, count: 16)
                    if format == .dxt3 {
                        // Four bits of opacity a pixel.
                        for index in 0..<16 {
                            let nibble = (source[at + index / 2] >> (index % 2 == 0 ? 0 : 4)) & 0x0F
                            alpha[index] = nibble * 17
                        }
                        at += 8
                    } else if format == .dxt5 {
                        // Two opacities, six or four between them, and three bits a pixel to pick one.
                        let first = Int(source[at]), second = Int(source[at + 1])
                        var levels = [first, second, 0, 0, 0, 0, 0, 255]
                        if first > second {
                            for step in 1...6 {
                                levels[step + 1] = ((7 - step) * first + step * second) / 7
                            }
                        } else {
                            for step in 1...4 {
                                levels[step + 1] = ((5 - step) * first + step * second) / 5
                            }
                        }
                        var bits: UInt64 = 0
                        for byte in 0..<6 {
                            bits |= UInt64(source[at + 2 + byte]) << (8 * UInt64(byte))
                        }
                        for index in 0..<16 {
                            alpha[index] = UInt8(levels[Int((bits >> (3 * UInt64(index))) & 7)])
                        }
                        at += 8
                    }

                    let first = Int(source[at]) | Int(source[at + 1]) << 8
                    let second = Int(source[at + 2]) | Int(source[at + 3]) << 8
                    // A color is packed into two bytes: five bits of red, six of green, five of blue.
                    func color(_ packed: Int) -> [Int] {
                        let red = (packed >> 11) & 31, green = (packed >> 5) & 63, blue = packed & 31
                        return [(red * 255 + 15) / 31, (green * 255 + 31) / 63, (blue * 255 + 15) / 31, 255]
                    }
                    var colors = [color(first), color(second), [0, 0, 0, 255], [0, 0, 0, 255]]
                    if format != .dxt1 || first > second {
                        colors[2] = (0..<3).map { (2 * colors[0][$0] + colors[1][$0]) / 3 } + [255]
                        colors[3] = (0..<3).map { (colors[0][$0] + 2 * colors[1][$0]) / 3 } + [255]
                    } else {
                        // DXT1 with the colors the other way round: one in between, and "nothing here".
                        colors[2] = (0..<3).map { (colors[0][$0] + colors[1][$0]) / 2 } + [255]
                        colors[3] = [0, 0, 0, 0]
                    }
                    for row in 0..<4 {
                        let picks = source[at + 4 + row]
                        for column in 0..<4 {
                            let x = blockX * 4 + column, y = blockY * 4 + row
                            guard x < width, y < height else { continue }
                            let picked = colors[Int((picks >> (2 * UInt8(column))) & 3)]
                            let target = (y * width + x) * 4
                            rgba[target] = UInt8(picked[0])
                            rgba[target + 1] = UInt8(picked[1])
                            rgba[target + 2] = UInt8(picked[2])
                            rgba[target + 3] = format == .dxt1 ? UInt8(picked[3]) : alpha[row * 4 + column]
                        }
                    }
                }
            }
        }
        return Data(rgba)
    }

    private static func cgImage(rgba: Data, width: Int, height: Int) -> CGImage? {
        guard rgba.count >= width * height * 4, let provider = CGDataProvider(data: rgba as CFData) else { return nil }
        // The opacity is not multiplied into the colors.
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: info,
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
