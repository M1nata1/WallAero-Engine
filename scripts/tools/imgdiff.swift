// imgdiff: compares pictures pixel by pixel, for scripts/compare.sh.
//
// Reads lines from standard input, each `<expected.png>\t<actual.png>\t<difference.png>`, and
// prints for each `<differing pixels>\t<all pixels>\t<largest channel difference>\t<mean
// difference>` — or `size\t…` when the two are not the same size, `missing\t…` when one cannot
// be read. A pixel differs when any of its channels is off by more than the tolerance
// (`--tolerance n`, 3 by default). Where pixels differ a difference picture is written: the
// expected one dimmed, the differing pixels magenta.
import AppKit
import CoreGraphics
import Foundation

var tolerance = 3
let arguments = CommandLine.arguments
if let index = arguments.firstIndex(of: "--tolerance"), index + 1 < arguments.count, let value = Int(arguments[index + 1]) {
    tolerance = value
}

func pixels(_ path: String) -> (width: Int, height: Int, bytes: [UInt8])? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
    let width = image.width, height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    return drawn ? (width, height, bytes) : nil
}

func write(_ bytes: [UInt8], width: Int, height: Int, to path: String) {
    var copy = bytes
    copy.withUnsafeMutableBytes { buffer in
        guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let image = context.makeImage() else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}

while let line = readLine() {
    let parts = line.components(separatedBy: "\t")
    guard parts.count >= 3 else { continue }
    guard let expected = pixels(parts[0]), let actual = pixels(parts[1]) else {
        print("missing\t0\t0\t0")
        fflush(stdout)
        continue
    }
    guard expected.width == actual.width, expected.height == actual.height else {
        print("size\t\(expected.width)x\(expected.height)\t\(actual.width)x\(actual.height)\t0")
        fflush(stdout)
        continue
    }
    let count = expected.width * expected.height
    var differing = 0, largest = 0, sum = 0
    var picture = [UInt8](repeating: 0, count: count * 4)
    expected.bytes.withUnsafeBufferPointer { a in
        actual.bytes.withUnsafeBufferPointer { b in
            for pixel in 0..<count {
                let at = pixel * 4
                var most = 0
                for channel in 0..<3 {
                    let off = abs(Int(a[at + channel]) - Int(b[at + channel]))
                    sum += off
                    if off > most { most = off }
                }
                if most > largest { largest = most }
                if most > tolerance {
                    differing += 1
                    picture[at] = 255; picture[at + 1] = 0; picture[at + 2] = 255
                } else {
                    picture[at] = a[at] / 4; picture[at + 1] = a[at + 1] / 4; picture[at + 2] = a[at + 2] / 4
                }
                picture[at + 3] = 255
            }
        }
    }
    if differing > 0 { write(picture, width: expected.width, height: expected.height, to: parts[2]) }
    print("\(differing)\t\(count)\t\(largest)\t\(String(format: "%.4f", Double(sum) / Double(count * 3)))")
    fflush(stdout)
}
