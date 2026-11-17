import AppKit
import WallpaperCore

/// Renders a web wallpaper to a picture without showing it: the library thumbnail, and the still
/// that goes to macOS as the regular wallpaper.
@MainActor
enum WebSnapshotter {
    /// - Parameters:
    ///   - size: the size to lay the page out at, in points; the picture is twice that in pixels
    ///     on a Retina Mac.
    ///   - forStill: render the picture for the lock screen, without the layers hidden from it.
    static func render(_ project: WebProject, size: NSSize, forStill: Bool = false) async -> CGImage? {
        // A scene the app draws itself is pictured as it is drawn on the desktop.
        if project.isScene, ScreenWallpaper.drawsScenesNatively, SceneProject.isNativelyPlayable(project.folder),
           let picture = await renderNatively(project.folder, size: size, forStill: forStill) {
            return picture
        }
        // Chromium draws the page off screen: no window is needed, and nothing appears.
        let view = WebWallpaperView(frame: NSRect(origin: .zero, size: size))
        view.rendersStill = forStill
        defer { view.unload() }

        view.setPlaying(true, rate: 1)
        view.show(project, watchingForChanges: false)
        await view.waitUntilLoaded()
        // Time for pictures and the first video frame to arrive.
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        return await view.snapshot()
    }

    private static func renderNatively(_ folder: URL, size: NSSize, forStill: Bool) async -> CGImage? {
        let view = NativeSceneView(frame: NSRect(origin: .zero, size: size))
        view.rendersStill = forStill
        view.hearsSound = false
        view.setAudio(muted: true, volume: 0)
        view.setPlaying(true, rate: 1)
        defer { view.unload() }
        // Ready with its first frame, or after a few seconds whatever became of it.
        let shown: Bool = await withCheckedContinuation { continuation in
            var resumed = false
            view.onReady = {
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: true)
            }
            if !view.show(folder: folder, watchingForChanges: false) {
                resumed = true
                continuation.resume(returning: false)
            }
        }
        guard shown else { return nil }
        // Time for pictures and the first video frame to arrive.
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        return view.snapshot()
    }

    /// The picture scaled down for the library grid.
    static func thumbnail(from image: CGImage, width: Int = 640) -> CGImage {
        guard image.width > width else { return image }
        let height = Int((Double(image.height) * Double(width) / Double(image.width)).rounded())
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            return image
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }
}
