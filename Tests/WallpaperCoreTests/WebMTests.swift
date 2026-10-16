import AVFoundation
import XCTest
@testable import WallpaperCore

final class WebMTests: XCTestCase {
    // MARK: - EBML

    func testSizesTakeTheShortestForm() {
        XCTAssertEqual([UInt8](EBML.size(0)), [0x80])
        XCTAssertEqual([UInt8](EBML.size(126)), [0xFE])
        // 127 in one byte would read as "unknown size".
        XCTAssertEqual([UInt8](EBML.size(127)), [0x40, 0x7F])
        XCTAssertEqual([UInt8](EBML.size(300)), [0x41, 0x2C])
        XCTAssertEqual([UInt8](EBML.size(5, width: 8)), [0x01, 0, 0, 0, 0, 0, 0, 5])
    }

    func testElementsCarryTheirIDAndSize() {
        XCTAssertEqual([UInt8](EBML.uint(0xD7, 1)), [0xD7, 0x81, 0x01])
        XCTAssertEqual([UInt8](EBML.string(0x86, "V_VP9")), [0x86, 0x85] + Array("V_VP9".utf8))
        XCTAssertEqual([UInt8](EBML.id(0x1A45_DFA3)), [0x1A, 0x45, 0xDF, 0xA3])
        XCTAssertEqual(EBML.void(96).count, 96)
        XCTAssertEqual(EBML.void(200).count, 200)
        XCTAssertEqual(EBML.void(2).count, 2)
    }

    func testWriterLaysOutAWebMFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).webm")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try WebMWriter(url: url, video: .init(width: 64, height: 32), audio: .init(channels: 2, preSkip: 312))
        for frame in 0..<100 {
            try writer.addVideo(Data([UInt8(frame), 1, 2, 3]), time: Int64(frame * 33), keyframe: frame % 30 == 0)
        }
        for packet in 0..<160 {
            try writer.addAudio(Data([9, 9]), time: Int64(packet * 20))
        }
        try writer.finish(duration: 3300)
        let data = try Data(contentsOf: url)
        func has(_ bytes: [UInt8]) -> Bool { data.range(of: Data(bytes)) != nil }
        XCTAssertTrue(data.starts(with: [0x1A, 0x45, 0xDF, 0xA3]))
        XCTAssertTrue(has(Array("webm".utf8)))
        XCTAssertTrue(has(Array("V_VP9".utf8)))
        XCTAssertTrue(has(Array("A_OPUS".utf8)))
        XCTAssertTrue(has(Array("OpusHead".utf8)))
        XCTAssertTrue(has([0x1C, 0x53, 0xBB, 0x6B]), "an index to seek by")
        XCTAssertTrue(has([0x11, 0x4D, 0x9B, 0x74]), "a seek head")
        // Four keyframes, four clusters.
        let cluster = Data([0x1F, 0x43, 0xB6, 0x75])
        var clusters = 0
        var from = data.startIndex
        while let found = data.range(of: cluster, in: from..<data.endIndex) {
            clusters += 1
            from = found.upperBound
        }
        XCTAssertEqual(clusters, 4)
        // The segment's size is the rest of the file.
        let segment = data.range(of: Data([0x18, 0x53, 0x80, 0x67]))!
        let sizeBytes = data[segment.upperBound..<segment.upperBound + 8]
        let size = sizeBytes.dropFirst().reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        XCTAssertEqual(Int(size), data.count - (segment.upperBound + 8))
    }

    // MARK: - Converting

    func testH264VideoNeedsConversionAndWebMDoesNot() async throws {
        let video = try await Self.makeH264Video(frames: 12)
        defer { try? FileManager.default.removeItem(at: video) }
        let isNeeded = await WebMediaConverter.needsConversion(video)
        XCTAssertTrue(isNeeded)
        let notMedia = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        try Data("not a video".utf8).write(to: notMedia)
        defer { try? FileManager.default.removeItem(at: notMedia) }
        let isNeededForText = await WebMediaConverter.needsConversion(notMedia)
        XCTAssertFalse(isNeededForText)
    }

    /// Needs the encoders built by scripts/codecs.sh; passed over without them.
    func testFolderConversionKeepsNamesAndOriginals() async throws {
        let library = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/codecs/libWallAeroCodecs.dylib")
        guard FileManager.default.fileExists(atPath: library.path) else {
            throw XCTSkip("scripts/codecs.sh has not been run")
        }
        WebMediaConverter.libraryURL = library
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("media"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let video = try await Self.makeH264Video(frames: 45)
        try FileManager.default.moveItem(at: video, to: folder.appendingPathComponent("media/clip.mp4"))

        let converted = await WebMediaConverter.convertFolder(folder)
        XCTAssertEqual(converted, ["media/clip.mp4"])
        let data = try Data(contentsOf: folder.appendingPathComponent("media/clip.mp4"))
        XCTAssertTrue(data.starts(with: [0x1A, 0x45, 0xDF, 0xA3]), "WebM under the old name")
        XCTAssertTrue(data.range(of: Data("V_VP9".utf8)) != nil)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(".originals/media/clip.mp4").path))
        // Done once: nothing is left to convert.
        let again = await WebMediaConverter.convertFolder(folder)
        XCTAssertEqual(again, [])
    }

    /// A short H.264 video of moving bars, made with AVFoundation.
    static func makeH264Video(frames: Int) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 160, AVVideoHeightKey: 96,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 160,
            kCVPixelBufferHeightKey as String: 96,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            guard let buffer else { continue }
            CVPixelBufferLockBaseAddress(buffer, [])
            let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
            let row = CVPixelBufferGetBytesPerRow(buffer)
            for y in 0..<96 {
                for x in 0..<160 {
                    let pixel = base + y * row + x * 4
                    pixel[0] = UInt8((x + frame * 4) % 256)
                    pixel[1] = UInt8(y * 2)
                    pixel[2] = 128
                    pixel[3] = 255
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
        }
        input.markAsFinished()
        await writer.finishWriting()
        return url
    }
}
