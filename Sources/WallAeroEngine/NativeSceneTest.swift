import AppKit
import MetalScene
import WallpaperCore

/// `--native-test <scene folder> <picture.png> [--after <seconds>] [--size <w> <h>] [--pointer-at <s> <x> <y>]
/// [--pointer-circle <seconds a turn>] [--shots <count> <seconds between>] [--screen <number>]`: plays a
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
        // `--screen <number>`: which of the Mac's screens the window opens on, 0 being the main one —
        // so that a long run does not cover the screen someone is working on.
        let screens = NSScreen.screens
        let screen = value("--screen").flatMap(Int.init).flatMap { screens.indices.contains($0) ? screens[$0] : nil }
        let corner = screen.map { NSPoint(x: $0.frame.minX + 40, y: $0.frame.minY + 40) } ?? NSPoint(x: 40, y: 40)
        let window = NSWindow(contentRect: NSRect(origin: corner, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
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
        // `--pointer-at <seconds> <x> <y>`: the pointer moves there then, in points from the top left.
        for (index, argument) in arguments.enumerated() where argument == "--pointer-at" && index + 3 < arguments.count {
            guard let moment = Double(arguments[index + 1]), let x = Double(arguments[index + 2]), let y = Double(arguments[index + 3]) else { continue }
            DispatchQueue.main.asyncAfter(deadline: .now() + moment) { player.pointer("move", x: x, y: y) }
        }
        // `--pointer-circle <seconds a turn>`: the pointer goes round the middle of the view,
        // clockwise as one looks at it, a third of the shorter side away, from the start to the
        // picture — for the wallpapers that follow the pointer, look at it or lean away from it.
        if let turn = value("--pointer-circle").flatMap(Double.init), turn > 0 {
            let radius = min(size.width, size.height) / 3
            let begun = Date()
            Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { _ in
                // From the top, clockwise: y is counted downward from the top left.
                let angle = Date().timeIntervalSince(begun) / turn * 2 * .pi - .pi / 2
                player.pointer("move", x: size.width / 2 + radius * cos(angle), y: size.height / 2 + radius * sin(angle))
            }
        }
        // `--press-at <seconds> <x> <y>`: the button goes down there then, and stays down.
        for (index, argument) in arguments.enumerated() where argument == "--press-at" && index + 3 < arguments.count {
            guard let moment = Double(arguments[index + 1]), let x = Double(arguments[index + 2]), let y = Double(arguments[index + 3]) else { continue }
            DispatchQueue.main.asyncAfter(deadline: .now() + moment) { player.pointer("down", x: x, y: y) }
        }
        // `--shots <count> <seconds between>`: a row of pictures from then on, each named after the
        // main picture plus its number — to see what moves or comes and goes from frame to frame.
        var shotsTake = 0.0
        if let index = arguments.firstIndex(of: "--shots"), index + 2 < arguments.count,
           let count = Int(arguments[index + 1]), let between = Double(arguments[index + 2]) {
            shotsTake = Double(count) * between
            for shot in 0..<count {
                DispatchQueue.main.asyncAfter(deadline: .now() + seconds + Double(shot) * between) {
                    guard let image = player.snapshot() else { return }
                    let name = request.output.deletingPathExtension().path + String(format: "-%03d.png", shot)
                    try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: name))
                    print("shot \(shot) at \(String(format: "%.3f", Date().timeIntervalSince(started)))")
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds + shotsTake) {
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
