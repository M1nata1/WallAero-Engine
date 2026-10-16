import AppKit
import CEFHost

/// Chromium, which draws the web wallpapers: started once, when the app starts.
@MainActor
enum Chromium {
    private(set) static var isRunning = false
    private static var temporaryCache: URL?

    /// Starts Chromium from the app's Frameworks folder, or, for a binary run from the package
    /// in development, from `build/cef` (see scripts/cef.sh). Without it web wallpapers stay black.
    static func start() {
        guard !isRunning, let folder = frameworksFolder else {
            if !isRunning { Log.playback.error("Chromium is missing; web wallpapers cannot be shown") }
            return
        }
        let port = ProcessInfo.processInfo.environment["WALLAERO_DEVTOOLS_PORT"].flatMap(Int32.init) ?? 0
        isRunning = CEFRuntime.start(withFrameworksFolder: folder.path, cacheFolder: cacheFolder.path, debuggingPort: port)
        if !isRunning {
            Log.playback.error("Chromium did not start")
        }
    }

    static func stop() {
        CEFRuntime.shutdown()
        isRunning = false
        if let temporaryCache {
            try? FileManager.default.removeItem(at: temporaryCache)
        }
    }

    private static var frameworksFolder: URL? {
        let name = "Chromium Embedded Framework.framework"
        let files = FileManager.default
        if let bundled = Bundle.main.privateFrameworksURL, files.fileExists(atPath: bundled.appendingPathComponent(name).path) {
            return bundled
        }
        #if DEBUG
        // Sources/WallAeroEngine/Engine/Chromium.swift → the package → build/cef.
        let built = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/cef", isDirectory: true)
        if files.fileExists(atPath: built.appendingPathComponent(name).path) {
            return built
        }
        #endif
        return nil
    }

    /// Where Chromium keeps what pages store, like their settings in local storage. Only one
    /// running Chromium may use a folder, so the helpers a developer runs next to the app in use
    /// get one of their own, gone when they quit.
    private static var cacheFolder: URL {
        let files = FileManager.default
        if CommandLine.arguments.dropFirst().contains(where: { $0.hasPrefix("--") }) {
            let folder = files.temporaryDirectory.appendingPathComponent("WallAeroEngine-\(ProcessInfo.processInfo.processIdentifier)",
                                                                       isDirectory: true)
            temporaryCache = folder
            return folder
        }
        let caches = files.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("com.fadevec.WallAeroEngine/Chromium", isDirectory: true)
    }
}
