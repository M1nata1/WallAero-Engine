import CoreGraphics
import XCTest
@testable import WallpaperCore

/// A thumbnail is to say which wallpaper it is: a black one gives way to the picture the wallpaper
/// came with, and frames that are black are passed over.
final class ThumbnailTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    private func picture(gray: CGFloat) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: gray, green: gray, blue: gray, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        return try XCTUnwrap(context.makeImage())
    }

    /// A library with one scene whose thumbnail has the given lightness, and a preview in its project.
    @MainActor
    private func library(thumbnail: CGFloat, preview: CGFloat?, previewName: String = "preview.jpg") throws -> (WallpaperLibrary, Wallpaper) {
        let id = UUID()
        let scene = root.appendingPathComponent("Web/\(id.uuidString)", isDirectory: true)
        let project = scene.appendingPathComponent(WallpaperEngineProjectFolder.folderName, isDirectory: true)
        let thumbnails = root.appendingPathComponent("Thumbnails", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: thumbnails, withIntermediateDirectories: true)
        try Data().write(to: scene.appendingPathComponent(SceneProject.entryFileName))
        try Thumbnailer.writeJPEG(picture(gray: thumbnail), to: thumbnails.appendingPathComponent("\(id.uuidString).jpg"))
        try JSONSerialization.data(withJSONObject: ["preview": previewName]).write(to: project.appendingPathComponent("project.json"))
        if let preview {
            try Thumbnailer.writeJPEG(picture(gray: preview), to: project.appendingPathComponent("preview.jpg"))
        }
        let item = Wallpaper(id: id, name: "Scene", kind: .web, fileName: "\(id.uuidString)/\(SceneProject.entryFileName)",
                             thumbnailFileName: "\(id.uuidString).jpg", sourceFormat: "SCENE", wasConverted: false,
                             pixelWidth: 0, pixelHeight: 0, duration: nil, hasAudio: true, fileSize: 0)
        try JSONEncoder().encode([item]).write(to: root.appendingPathComponent("library.json"))
        return (WallpaperLibrary(rootURL: root), item)
    }

    func testBlackPicturesAreToldFromDarkOnes() throws {
        XCTAssertTrue(Thumbnailer.isNearlyBlack(try picture(gray: 0.02)))
        XCTAssertFalse(Thumbnailer.isNearlyBlack(try picture(gray: 0.2)))
    }

    @MainActor
    func testABlackThumbnailGivesWayToThePreview() async throws {
        let (library, item) = try library(thumbnail: 0, preview: 0.6)
        let lighter = await library.lighterThumbnail(for: item)
        XCTAssertEqual(try XCTUnwrap(lighter).width, 64)
    }

    @MainActor
    func testAThumbnailThatShowsSomethingStays() async throws {
        let (library, item) = try library(thumbnail: 0.4, preview: 0.6)
        let lighter = await library.lighterThumbnail(for: item)
        XCTAssertNil(lighter)
    }

    @MainActor
    func testAPreviewAsBlackIsNoImprovement() async throws {
        let (library, item) = try library(thumbnail: 0, preview: 0)
        let lighter = await library.lighterThumbnail(for: item)
        XCTAssertNil(lighter)
    }

    @MainActor
    func testAPreviewOutsideTheProjectIsNotRead() async throws {
        let (library, item) = try library(thumbnail: 0, preview: 0.6, previewName: "../preview.jpg")
        let lighter = await library.lighterThumbnail(for: item)
        XCTAssertNil(lighter)
    }
}
