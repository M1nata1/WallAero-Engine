import XCTest
@testable import WallpaperCore

/// Videos the Mac's media engine decodes are left as they are; one it does not is made over.
final class HardwareVideoTests: XCTestCase {
    func testAVideoTheMediaEngineDecodesIsLeftAlone() async throws {
        let url = try await WebMTests.makeH264Video(frames: 30)
        defer { try? FileManager.default.removeItem(at: url) }
        let before = try Data(contentsOf: url)
        let decoded = await HardwareVideo.isDecodedInHardware(url)
        let changed = try await HardwareVideo.makeDecodableInHardware(url)
        XCTAssertFalse(changed && decoded)
        if decoded {
            XCTAssertEqual(try Data(contentsOf: url), before)
        }
    }

    func testAFileWithoutAVideoIsNotTouched() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        try Data("not a video".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let isDecoded = await HardwareVideo.isDecodedInHardware(url)
        XCTAssertTrue(isDecoded)
        let changed = try await HardwareVideo.makeDecodableInHardware(url)
        XCTAssertFalse(changed)
    }

    /// Not a test: with WALLAERO_HEVC_DEMO set to a video file, makes it over in place if the
    /// media engine cannot decode it.
    func testMakeOver() async throws {
        guard let path = ProcessInfo.processInfo.environment["WALLAERO_HEVC_DEMO"] else { throw XCTSkip("no video asked for") }
        let url = URL(fileURLWithPath: path)
        let changed = try await HardwareVideo.makeDecodableInHardware(url)
        print("made over:", changed, "decoded in hardware now:", await HardwareVideo.isDecodedInHardware(url))
    }
}
