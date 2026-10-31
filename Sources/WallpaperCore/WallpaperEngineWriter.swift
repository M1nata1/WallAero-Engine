import Foundation

/// Writes files in Wallpaper Engine's own formats, as Wallpaper Engine itself writes them, so
/// that a wallpaper made in the app opens in Wallpaper Engine: textures and the package a
/// scene's files are put together in.
public enum WallpaperEngineWriter {
    /// A texture of a picture, kept whole as the PNG or JPEG file it is — as Wallpaper Engine
    /// keeps a picture it was given: the texture's canvas has sides that are powers of two,
    /// the picture's own size is given next to it, and there is one picture, at full size.
    /// - Parameters:
    ///   - clamped: whether the picture ends at its edges rather than repeating.
    ///   - smooth: whether it is smoothed when drawn larger or smaller.
    ///   - color: the color the header gives, as Wallpaper Engine gives a map's color at rest.
    public static func texture(picture file: Data, width: Int, height: Int, clamped: Bool = true, smooth: Bool = true,
                               color: UInt32 = 0xFF00_0000) -> Data {
        // FreeImage's numbers for the kinds of picture file.
        let kind: Int32 = file.starts(with: [0xFF, 0xD8]) ? 2 : 13
        var data = Data()
        data += zeroText("TEXV0005")
        data += zeroText("TEXI0001")
        data += int(0) // four bytes a pixel, as the format of the canvas
        data += int(flags(clamped: clamped, smooth: smooth, video: false))
        data += int(Int32(powerOfTwo(width)))
        data += int(Int32(powerOfTwo(height)))
        data += int(Int32(width))
        data += int(Int32(height))
        data += uint(color)
        data += zeroText("TEXB0003")
        data += int(1) // one picture
        data += int(kind)
        data += int(1) // at one size
        data += int(Int32(width))
        data += int(Int32(height))
        data += int(0) // not compressed
        data += int(0)
        data += int(Int32(file.count))
        data += file
        return data
    }

    /// A texture that holds a video, an MP4 file, in place of a picture.
    public static func texture(video file: Data, width: Int, height: Int, clamped: Bool = true) -> Data {
        var data = Data()
        data += zeroText("TEXV0005")
        data += zeroText("TEXI0001")
        data += int(0)
        data += int(flags(clamped: clamped, smooth: true, video: true))
        data += int(Int32(width))
        data += int(Int32(height))
        data += int(Int32(width))
        data += int(Int32(height))
        data += uint(0)
        data += zeroText("TEXB0004")
        data += int(1)
        data += int(-1) // no picture file
        data += int(0)
        data += int(1)
        data += int(Int32(width))
        data += int(Int32(height))
        data += int(0)
        data += int(0)
        data += int(Int32(file.count))
        data += file
        return data
    }

    /// The files of a scene in one package, `scene.pkg`: the names with where each is, then
    /// the files one after another.
    public static func package(_ files: [(name: String, data: Data)]) -> Data {
        var head = Data()
        head += text("PKGV0001")
        head += uint(UInt32(files.count))
        var offset: UInt32 = 0
        for file in files {
            head += text(file.name)
            head += uint(offset)
            head += uint(UInt32(file.data.count))
            offset += UInt32(file.data.count)
        }
        var data = head
        for file in files {
            data += file.data
        }
        return data
    }

    // MARK: - Parts

    /// Bits of a texture's flags: 1 for "not smoothed", 2 for "ends at its edges", 32 for a video.
    private static func flags(clamped: Bool, smooth: Bool, video: Bool) -> Int32 {
        (smooth ? 0 : 1) | (clamped ? 2 : 0) | (video ? 32 : 0)
    }

    static func powerOfTwo(_ value: Int) -> Int {
        var side = 1
        while side < value {
            side <<= 1
        }
        return side
    }

    private static func int(_ value: Int32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    private static func uint(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    private static func zeroText(_ text: String) -> Data {
        Data(text.utf8) + Data([0])
    }

    /// A text with its length before it.
    private static func text(_ text: String) -> Data {
        let bytes = Data(text.utf8)
        return uint(UInt32(bytes.count)) + bytes
    }
}
