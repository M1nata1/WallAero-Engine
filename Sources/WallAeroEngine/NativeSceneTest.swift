import AppKit
import MetalScene
import WallpaperCore

/// `--native-test <scene folder> <picture.png> [--after <seconds>] [--size <w> <h>]`: plays a
/// scene of Wallpaper Engine's with the app's own Metal renderer (`MetalScenePlayer`) in a window
/// nothing covers, then takes a picture of a frame and prints what the player and the renderer
/// have to say — as `--engine-test` does with Chromium, to be compared with it.
enum NativeSceneTest {
    static var request: (folder: URL, output: URL)? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--native-test"), index + 2 < arguments.count else { return nil }
        return (URL(fileURLWithPath: arguments[index + 1], isDirectory: true), URL(fileURLWithPath: arguments[index + 2]))
    }

    private static func value(_ option: String) -> String? {
        let arguments = CommandLine.arguments
        return arguments.firstIndex(of: option).flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
    }

    static func run(_ request: (folder: URL, output: URL)) {
        NSApp.setActivationPolicy(.accessory)
        var size = NSSize(width: 960, height: 540)
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--size"), index + 2 < arguments.count,
           let width = Double(arguments[index + 1]), let height = Double(arguments[index + 2]) {
            size = NSSize(width: width, height: height)
        }
        if arguments.contains("--full-screen"), let screen = NSScreen.main { size = screen.frame.size }
        let seconds = value("--after").flatMap(Double.init) ?? 3
        guard let player = MetalScenePlayer(folder: request.folder, engineScript: WallpaperEngineRuntime.script) else {
            print("no Metal here")
            exit(1)
        }
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: 40, y: 40), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        if arguments.contains("--full-screen"), let screen = NSScreen.main { window.setFrame(screen.frame, display: false) }
        let view = NSView(frame: NSRect(origin: .zero, size: size))
        view.wantsLayer = true
        view.layer = player.layer
        window.contentView = view
        window.orderFrontRegardless()
        player.frameRate = value("--fps").flatMap(Int.init) ?? 0
        player.setViewSize(size, scale: window.backingScaleFactor)
        let settings = SceneSettings(sceneFile: request.folder.appendingPathComponent("scene.json"))
        player.videoFiles = WallpaperEngineProjectFolder.nativeVideos(scene: request.folder)
        let started = Date()
        player.start(settings: settings.settings, changes: settings.changes, fit: settings.fit, position: settings.position)
        print("started in \(String(format: "%.2f", Date().timeIntervalSince(started))) s")
        fflush(stdout)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            if let image = player.snapshot() {
                let bitmap = NSBitmapImageRep(cgImage: image)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: request.output)
                print("wrote \(request.output.path) (\(image.width)×\(image.height))")
            } else {
                print("no picture could be taken")
            }
            print(player.report)
            for note in player.notes { print("native: \(note)") }
            if let script = value("--eval-end") { print("eval: \(player.evaluate(script) ?? "nothing")") }
            exit(0)
        }
    }
}
